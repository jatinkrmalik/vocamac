// UpdateChecker.swift
// VocaMac
//
// Checks GitHub Releases for new versions and downloads DMG updates.

import Foundation
import SwiftUI
import AppKit
import CryptoKit

enum UpdateCheckerError: LocalizedError {
    case invalidResponse
    case invalidStatusCode(Int)
    case noDMGAsset
    case failedToMoveDownload
    case checksumMismatch
    case downloadCancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from update server"
        case .invalidStatusCode(let statusCode):
            return "Update check failed (HTTP \(statusCode))"
        case .noDMGAsset:
            return "No DMG asset found in latest release"
        case .failedToMoveDownload:
            return "Failed to store downloaded update"
        case .checksumMismatch:
            return "Downloaded update failed integrity verification"
        case .downloadCancelled:
            return "Download was cancelled"
        }
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var updateState: UpdateState = .idle

    private let apiURL = URL(string: "https://api.github.com/repos/jatinkrmalik/vocamac/releases/latest")!
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let lastCheckKey = "vocamac.update.lastCheck"
    private let skippedVersionKey = "vocamac.update.skippedVersion"

    func checkOnLaunchIfNeeded() async {
        let lastCheckTime = UserDefaults.standard.double(forKey: lastCheckKey)
        let shouldCheck = Date().timeIntervalSince1970 - lastCheckTime > checkInterval
        guard shouldCheck else { return }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard updateState != .checking else { return }
        updateState = .checking

        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            let remoteVersion = normalizeVersion(release.tagName)
            let currentVersion = normalizeVersion(currentAppVersion())

            if UserDefaults.standard.string(forKey: skippedVersionKey) == remoteVersion {
                updateState = .upToDate
                return
            }

            if isNewerVersion(remote: remoteVersion, current: currentVersion) {
                guard let info = buildUpdateInfo(from: release) else {
                    throw UpdateCheckerError.noDMGAsset
                }
                updateState = .updateAvailable(info)
                VocaLogger.info(.updateChecker, "Update available: \(info.tagName)")
            } else {
                updateState = .upToDate
            }
        } catch {
            updateState = .error(error.localizedDescription)
            VocaLogger.error(.updateChecker, "Update check failed: \(error.localizedDescription)")
        }
    }

    func downloadUpdate(_ info: UpdateInfo) async {
        updateState = .downloading(progress: 0, bytesDownloaded: 0, totalBytes: Int64(info.dmgSize), estimatedSecondsRemaining: 0)
        VocaLogger.info(.updateChecker, "Starting download: \(info.dmgURL)")

        do {
            let fileURL = try await downloadDMG(from: info.dmgURL, totalSize: Int64(info.dmgSize), expectedSHA256: info.sha256)
            updateState = .readyToInstall(dmgPath: fileURL)
            VocaLogger.info(.updateChecker, "Update downloaded: \(fileURL.lastPathComponent)")
        } catch {
            updateState = .error(error.localizedDescription)
            VocaLogger.error(.updateChecker, "Update download failed: \(error.localizedDescription)")
        }
    }

    func openDMG(at url: URL) {
        NSWorkspace.shared.open(url)
    }

    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
        updateState = .upToDate
    }

    func dismiss() {
        updateState = .idle
    }

    func normalizeVersion(_ version: String) -> String {
        var normalized = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("v") {
            normalized.removeFirst()
        }

        let parts = normalized.split(separator: ".").map(String.init)
        switch parts.count {
        case 0:
            return "0.0.0"
        case 1:
            return "\(parts[0]).0.0"
        case 2:
            return "\(parts[0]).\(parts[1]).0"
        default:
            return "\(parts[0]).\(parts[1]).\(parts[2])"
        }
    }

    func isNewerVersion(remote: String, current: String) -> Bool {
        func parse(_ version: String) -> (Int, Int, Int) {
            let values = version.split(separator: ".").compactMap { Int($0) }
            let major = values.indices.contains(0) ? values[0] : 0
            let minor = values.indices.contains(1) ? values[1] : 0
            let patch = values.indices.contains(2) ? values[2] : 0
            return (major, minor, patch)
        }

        return parse(remote) > parse(current)
    }

    private func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VocaMac", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateCheckerError.invalidStatusCode(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func buildUpdateInfo(from release: GitHubRelease) -> UpdateInfo? {
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") && $0.name.contains("arm64") }) else {
            return nil
        }

        let sha256: String?
        if let digest = dmgAsset.digest, digest.hasPrefix("sha256:") {
            sha256 = String(digest.dropFirst("sha256:".count))
        } else {
            sha256 = nil
        }

        return UpdateInfo(
            version: normalizeVersion(release.tagName),
            tagName: release.tagName,
            releaseNotes: release.body,
            releasePageURL: release.htmlURL,
            dmgURL: dmgAsset.browserDownloadURL,
            dmgSize: dmgAsset.size,
            sha256: sha256
        )
    }

    // MARK: - Download with Progress

    /// Downloads a DMG using AsyncStream-bridged delegate for real-time progress.
    private func downloadDMG(from url: URL, totalSize: Int64, expectedSHA256: String?) async throws -> URL {
        let delegate = DownloadDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let task = session.downloadTask(with: url)
        task.resume()

        let startTime = Date()
        var fileURL: URL?

        for await event in delegate.events {
            switch event {
            case .progress(let bytesWritten, let totalExpected):
                let total = totalExpected > 0 ? totalExpected : totalSize
                let fraction = total > 0 ? Double(bytesWritten) / Double(total) : 0
                let elapsed = Date().timeIntervalSince(startTime)
                let speed = elapsed > 0 ? Double(bytesWritten) / elapsed : 0
                let remaining = speed > 0 ? Double(total - bytesWritten) / speed : 0
                updateState = .downloading(
                    progress: min(fraction, 1.0),
                    bytesDownloaded: bytesWritten,
                    totalBytes: total,
                    estimatedSecondsRemaining: remaining
                )
            case .completed(let url):
                fileURL = url
            case .failed(let error):
                session.finishTasksAndInvalidate()
                throw error
            }
        }

        session.finishTasksAndInvalidate()

        guard let downloadedFile = fileURL else {
            throw UpdateCheckerError.downloadCancelled
        }

        // Verify SHA-256
        if let expectedSHA256 {
            updateState = .verifying
            VocaLogger.info(.updateChecker, "Verifying SHA-256 checksum...")
            let data = try Data(contentsOf: downloadedFile, options: .mappedIfSafe)
            let hash = SHA256.hash(data: data)
            let actualSHA256 = hash.compactMap { String(format: "%02x", $0) }.joined()
            guard expectedSHA256.lowercased() == actualSHA256.lowercased() else {
                try? FileManager.default.removeItem(at: downloadedFile)
                throw UpdateCheckerError.checksumMismatch
            }
        }

        // Move to final location
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destinationURL)

        do {
            try FileManager.default.moveItem(at: downloadedFile, to: destinationURL)
        } catch {
            throw UpdateCheckerError.failedToMoveDownload
        }

        return destinationURL
    }
}

// MARK: - Download Events

private enum DownloadEvent {
    case progress(bytesWritten: Int64, totalBytes: Int64)
    case completed(URL)
    case failed(Error)
}

/// URLSession download delegate that bridges callbacks to an AsyncStream.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let events: AsyncStream<DownloadEvent>
    private let continuation: AsyncStream<DownloadEvent>.Continuation

    override init() {
        let (stream, cont) = AsyncStream.makeStream(of: DownloadEvent.self)
        self.events = stream
        self.continuation = cont
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Move file before URLSession deletes it
        let savedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".dmg")
        do {
            try FileManager.default.moveItem(at: location, to: savedURL)

            if let httpResponse = downloadTask.response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                continuation.yield(.failed(UpdateCheckerError.invalidStatusCode(httpResponse.statusCode)))
            } else {
                continuation.yield(.completed(savedURL))
            }
        } catch {
            continuation.yield(.failed(UpdateCheckerError.failedToMoveDownload))
        }
        continuation.finish()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuation.yield(.failed(error))
            continuation.finish()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        continuation.yield(.progress(bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite))
    }
}

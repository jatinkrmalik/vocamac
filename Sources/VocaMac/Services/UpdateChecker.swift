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
        do {
            updateState = .downloading(progress: 0)
            let fileURL = try await downloadDMG(from: info.dmgURL, expectedSHA256: info.sha256)
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

    private func downloadDMG(from url: URL, expectedSHA256: String?) async throws -> URL {
        let delegate = DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor in
                self?.updateState = .downloading(progress: progress)
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempFileURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckerError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw UpdateCheckerError.invalidStatusCode(httpResponse.statusCode)
        }

        if let expectedSHA256 {
            let data = try Data(contentsOf: tempFileURL, options: .mappedIfSafe)
            let hash = SHA256.hash(data: data)
            let actualSHA256 = hash.compactMap { String(format: "%02x", $0) }.joined()
            guard expectedSHA256.lowercased() == actualSHA256.lowercased() else {
                throw UpdateCheckerError.checksumMismatch
            }
        }

        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destinationURL)

        do {
            try FileManager.default.moveItem(at: tempFileURL, to: destinationURL)
        } catch {
            throw UpdateCheckerError.failedToMoveDownload
        }

        return destinationURL
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
}

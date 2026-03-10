// Logger.swift
// VocaMac
//
// System-wide logging framework with os.Logger integration,
// persistent file logging, and automatic log rotation.

import Foundation
import os

/// Log categories for different services and components
enum LogCategory: String {
    case appState = "AppState"
    case audioEngine = "AudioEngine"
    case whisperService = "WhisperService"
    case hotKeyManager = "HotKeyManager"
    case modelManager = "ModelManager"
    case soundManager = "SoundManager"
    case textInjector = "TextInjector"
    case cursorOverlay = "CursorOverlay"
    case onboarding = "Onboarding"
    case general = "General"
}

/// Log levels for filtering and categorization
enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

/// Unified logging framework for VocaMac
/// Combines os.Logger (Console.app integration) with persistent file logging
final class VocaLogger {
    // MARK: - Singleton

    static let shared = VocaLogger()

    // MARK: - Properties

    private let logDirectory: URL
    private let logFileURL: URL
    private let fileQueue = DispatchQueue(label: "com.vocamac.logger.file", attributes: .initiallyInactive)
    private let osLogger: os.Logger
    private var logFileHandle: FileHandle?
    private let logMaxSize = 5_000_000  // 5 MB
    private let maxRotatedFiles = 3
    private var currentLogLevel: LogLevel = .info

    // MARK: - Initialization

    private init() {
        // Setup log directory
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.logDirectory = appSupportURL.appendingPathComponent("VocaMac/logs", isDirectory: true)

        self.logFileURL = logDirectory.appendingPathComponent("vocamac.log")

        // Ensure log directory exists
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)

        // Initialize os.Logger
        self.osLogger = os.Logger(subsystem: "com.vocamac", category: "general")

        // Activate file queue
        fileQueue.activate()

        // Open or create log file
        fileQueue.async {
            self.setupLogFile()
        }
    }

    // MARK: - Public API

    /// Set the global log level for file and console output
    static func setLogLevel(_ level: LogLevel) {
        VocaLogger.shared.currentLogLevel = level
    }

    /// Log a debug message
    static func debug(_ category: LogCategory, _ message: String) {
        VocaLogger.shared.log(message, level: .debug, category: category)
    }

    /// Log an info message
    static func info(_ category: LogCategory, _ message: String) {
        VocaLogger.shared.log(message, level: .info, category: category)
    }

    /// Log a warning message
    static func warning(_ category: LogCategory, _ message: String) {
        VocaLogger.shared.log(message, level: .warning, category: category)
    }

    /// Log an error message
    static func error(_ category: LogCategory, _ message: String) {
        VocaLogger.shared.log(message, level: .error, category: category)
    }

    /// Get the URL of the active log file
    static func logFileURL() -> URL {
        VocaLogger.shared.logFileURL
    }

    /// Get the log directory URL
    static func logDirectory() -> URL {
        VocaLogger.shared.logDirectory
    }

    /// Get the approximate number of log entries in the current log file
    static var logEntryCount: Int {
        guard let content = try? String(contentsOf: VocaLogger.shared.logFileURL, encoding: .utf8) else {
            return 0
        }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    /// Read the last N lines from the log file
    static func readLastLines(_ count: Int = 500) -> [String] {
        VocaLogger.shared.getLastLines(count)
    }

    /// Export logs as a formatted string with system info header
    static func exportLogs(lastLines: Int = 500) -> String {
        VocaLogger.shared.formatExportedLogs(lastLines: lastLines)
    }

    // MARK: - Private Methods

    private func log(_ message: String, level: LogLevel, category: LogCategory) {
        // Check log level filter
        guard shouldLog(level: level) else { return }

        // Format the log message
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedMessage = "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(message)"

        // Write to os.Logger
        let osLogType: OSLogType = level == .error ? .error : (level == .warning ? .default : .info)
        osLogger.log(level: osLogType, "\(formattedMessage)")

        // Write to persistent file
        fileQueue.async {
            self.writeToFile(formattedMessage)
        }
    }

    private func shouldLog(level: LogLevel) -> Bool {
        switch (currentLogLevel, level) {
        case (.debug, _):
            return true
        case (.info, .debug):
            return false
        case (.info, _):
            return true
        case (.warning, .debug), (.warning, .info):
            return false
        case (.warning, _):
            return true
        case (.error, .error):
            return true
        case (.error, _):
            return false
        }
    }

    private func setupLogFile() {
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }

        // Open file handle for appending
        logFileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        if logFileHandle == nil {
            logFileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        }
        logFileHandle?.seekToEndOfFile()

        // Check if rotation is needed
        checkAndRotateIfNeeded()
    }

    private func writeToFile(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }

        if let handle = logFileHandle {
            handle.write(data)
            handle.synchronizeFile()
        }

        // Check if rotation is needed
        checkAndRotateIfNeeded()
    }

    private func checkAndRotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? Int else {
            return
        }

        if size > logMaxSize {
            performRotation()
        }
    }

    private func performRotation() {
        // Close current file handle
        logFileHandle?.closeFile()
        logFileHandle = nil

        // Rotate existing log files
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let oldName = "vocamac.\(i).log"
            let newName = "vocamac.\(i + 1).log"
            let oldURL = logDirectory.appendingPathComponent(oldName)
            let newURL = logDirectory.appendingPathComponent(newName)

            if FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
            }
        }

        // Move current log to vocamac.1.log
        let rotatedURL = logDirectory.appendingPathComponent("vocamac.1.log")
        try? FileManager.default.moveItem(at: logFileURL, to: rotatedURL)

        // Remove oldest rotated file if it exceeds max count
        let oldestURL = logDirectory.appendingPathComponent("vocamac.\(maxRotatedFiles + 1).log")
        try? FileManager.default.removeItem(at: oldestURL)

        // Setup new log file
        setupLogFile()
    }

    private func getLastLines(_ count: Int) -> [String] {
        var allLines: [String] = []

        // Read current log file
        if let currentContent = try? String(contentsOf: logFileURL, encoding: .utf8) {
            allLines.append(contentsOf: currentContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        }

        // Read rotated log files in reverse order (newest first)
        for i in 1...maxRotatedFiles {
            let rotatedURL = logDirectory.appendingPathComponent("vocamac.\(i).log")
            if let content = try? String(contentsOf: rotatedURL, encoding: .utf8) {
                allLines.insert(contentsOf: content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).reversed(), at: 0)
            }
        }

        // Return last N lines
        return Array(allLines.suffix(count))
    }

    private func formatExportedLogs(lastLines: Int = 500) -> String {
        var result = ""

        // Add system info header
        result += "=== VocaMac Debug Log Export ===\n"
        result += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n"

        // Add system information
        let capabilities = SystemInfo.detect()
        result += "Device: \(capabilities.processorName)\n"
        result += "Architecture: \(capabilities.isAppleSilicon ? "Apple Silicon (ARM64)" : "Intel (x86_64)")\n"
        result += "RAM: \(capabilities.physicalMemoryGB) GB\n"
        result += "CPU Cores: \(capabilities.coreCount)\n"

        // App version
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            result += "App Version: \(appVersion)\n"
        }

        result += "================================\n\n"

        // Add log lines
        let lines = getLastLines(lastLines)
        for line in lines {
            if !line.isEmpty {
                result += line + "\n"
            }
        }

        return result
    }
}

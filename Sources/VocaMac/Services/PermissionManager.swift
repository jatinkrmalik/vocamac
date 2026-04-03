// PermissionManager.swift
// VocaMac
//
// Manages system permission checking, requesting, and polling.
// Extracts permission logic from AppState for focused responsibility.

import Foundation
import AppKit
import Combine

/// Manages system permissions: microphone, accessibility, and input monitoring.
///
/// Accessibility and Input Monitoring permissions don't provide callback-based APIs,
/// so this manager polls to detect changes when the user grants access in System Settings.
@MainActor
final class PermissionManager: ObservableObject {

    // MARK: - Published State

    /// Microphone permission status
    @Published var micPermission: PermissionStatus = .notDetermined

    /// Accessibility permission status
    @Published var accessibilityPermission: PermissionStatus = .notDetermined

    /// Input Monitoring permission status
    @Published var inputMonitoringPermission: PermissionStatus = .notDetermined

    // MARK: - Dependencies

    private let audioEngine: AudioEngine
    private let hotKeyManager: HotKeyManager

    // MARK: - Private

    /// Timer that periodically polls permissions until all are granted.
    private var permissionPollTimer: Timer?

    /// Called when all permissions are granted and the hotkey listener should start.
    var onAllPermissionsGranted: (() -> Void)?

    // MARK: - Initialization

    init(audioEngine: AudioEngine, hotKeyManager: HotKeyManager) {
        self.audioEngine = audioEngine
        self.hotKeyManager = hotKeyManager
    }

    // MARK: - Permission Checking

    /// Whether all required permissions are granted.
    var allPermissionsGranted: Bool {
        micPermission == .granted &&
        accessibilityPermission == .granted &&
        inputMonitoringPermission == .granted
    }

    /// Re-check all permission statuses from the system.
    func checkPermissions() {
        micPermission = audioEngine.checkPermissionStatus()

        let accessibilityGranted = HotKeyManager.checkAccessibilityPermission(prompt: false)
        accessibilityPermission = accessibilityGranted ? .granted : .denied

        let inputMonitoringGranted = checkInputMonitoringPermission()
        inputMonitoringPermission = inputMonitoringGranted ? .granted : .denied
    }

    /// Check Input Monitoring permission using multiple strategies since no
    /// single approach is 100% reliable:
    /// 1. If HotKeyManager created a tap, check if macOS has disabled it (revocation)
    /// 2. Try creating a fresh `.cghidEventTap` (same type HotKeyManager uses)
    private func checkInputMonitoringPermission() -> Bool {
        // Strategy 1: If HotKeyManager has an active tap, check if macOS disabled it.
        if hotKeyManager.isListening, let tap = hotKeyManager.activeEventTap {
            return CGEvent.tapIsEnabled(tap: tap)
        }

        // Strategy 2: Try creating a fresh .cghidEventTap — the same type
        // HotKeyManager uses. More accurate than .cgSessionEventTap which
        // may inherit Terminal's permissions when launched from CLI.
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }

    // MARK: - Permission Requests

    /// Request microphone permission. Opens System Settings if already denied.
    func requestMicrophonePermission() {
        if micPermission == .denied {
            openMicrophoneSettings()
            return
        }

        audioEngine.requestPermission { [weak self] granted in
            Task { @MainActor in
                self?.micPermission = granted ? .granted : .denied
            }
        }
    }

    /// Open the Microphone privacy pane in System Settings.
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkPermissions()
        }
    }

    /// Prompt the user to grant Accessibility permission.
    func requestAccessibilityPermission() {
        let _ = HotKeyManager.checkAccessibilityPermission(prompt: true)
        startPermissionPolling()
    }

    /// Trigger Input Monitoring permission dialog and open System Settings.
    func requestInputMonitoringPermission() {
        // Attempting to create an event tap triggers macOS to auto-add
        // the app to the Input Monitoring list in System Settings.
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        if let tap = tap {
            CFMachPortInvalidate(tap)
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }

        startPermissionPolling()
    }

    // MARK: - Permission Polling

    /// Start polling permissions every 3 seconds until all are granted.
    func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        guard !allPermissionsGranted else { return }

        VocaLogger.debug(.appState, "Starting permission polling")
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.checkPermissions()

                // Notify when all permissions granted and hotkey can start
                if self.accessibilityPermission == .granted &&
                    self.inputMonitoringPermission == .granted &&
                    !self.hotKeyManager.isListening {
                    self.onAllPermissionsGranted?()
                }

                if self.allPermissionsGranted {
                    self.stopPermissionPolling()
                }
            }
        }
    }

    /// Stop the permission polling timer.
    func stopPermissionPolling() {
        VocaLogger.debug(.appState, "Stopping permission polling — all permissions granted")
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
}

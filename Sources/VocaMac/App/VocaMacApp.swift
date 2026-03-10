// VocaMacApp.swift
// VocaMac
//
// Main entry point for the VocaMac application.
// Configures the app as a menu bar-only application (no Dock icon).

import SwiftUI

/// Manages the settings window for menu-bar-only apps
final class SettingsWindowManager: ObservableObject {
    private var settingsWindow: NSWindow?

    func open(appState: AppState) {
        // If window already exists, just bring it to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the settings view
        let settingsView = SettingsView()
            .environmentObject(appState)

        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VocaMac Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window

        // Temporarily show in dock so the window can receive focus
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Watch for window close to hide from dock again
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
            // Hide from dock again when settings closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

/// Manages the onboarding window
final class OnboardingWindowManager: ObservableObject {
    private var onboardingWindow: NSWindow?
    var onCompletion: (() -> Void)?

    func open(appState: AppState) {
        // If window already exists, just bring it to front
        if let window = onboardingWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the onboarding view
        let onboardingView = OnboardingView()
            .environmentObject(appState)

        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to VocaMac"
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.onboardingWindow = window

        // Show in dock
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Watch for window close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onboardingWindow = nil
            // Hide from dock when onboarding closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        // Monitor app state for onboarding completion on main thread
        DispatchQueue.main.async {
            self.monitorOnboardingCompletion(appState: appState)
        }
    }

    private func monitorOnboardingCompletion(appState: AppState) {
        Task {
            while self.onboardingWindow?.isVisible == true {
                await MainActor.run {
                    if appState.hasCompletedOnboarding {
                        self.onboardingWindow?.close()
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)  // Check every 100ms
            }
        }
    }
}

@main
struct VocaMacApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsManager = SettingsWindowManager()
    @StateObject private var onboardingManager = OnboardingWindowManager()

    var body: some Scene {
        // Menu bar presence — the primary UI for VocaMac
        MenuBarExtra {
            MenuBarView(settingsManager: settingsManager)
                .environmentObject(appState)
        } label: {
            MenuBarIcon(appStatus: appState.appStatus, audioLevel: appState.audioLevel)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        // Ensure only one instance of VocaMac is running
        Self.ensureSingleInstance()

        // For .app bundles, Dock hiding is handled by LSUIElement=true in Info.plist.
        // For direct binary execution, we set it programmatically.
        DispatchQueue.main.async {
            NSApp?.setActivationPolicy(.accessory)
        }

        // Listen for "Show Setup Wizard" requests from Settings
        NotificationCenter.default.addObserver(
            forName: .showOnboarding,
            object: nil,
            queue: .main
        ) { [self] _ in
            self.onboardingManager.open(appState: self.appState)
        }
    }

    /// Terminate any other running instances of VocaMac
    private static func ensureSingleInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.vocamac.app")

        for app in runningApps where app.processIdentifier != currentPID {
            NSLog("[VocaMac] Terminating previous instance (PID %d)", app.processIdentifier)
            app.terminate()
        }

        // Also kill by process name for direct binary execution (no bundle ID)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "VocaMac"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pids = output.split(separator: "\n").compactMap { Int32($0) }
                for pid in pids where pid != currentPID {
                    NSLog("[VocaMac] Killing previous VocaMac process (PID %d)", pid)
                    kill(pid, SIGTERM)
                }
            }
        } catch {
            // pgrep not found or failed — not critical
        }
    }
}

// MARK: - Menu Bar Icon

/// Renders a mic icon in the menu bar with color changes based on app status.
///
/// Uses NSImage to create properly tinted menu bar icons because MenuBarExtra's
/// label treats SwiftUI `.foregroundStyle()` colors as template images, stripping
/// color. By setting `isTemplate = false` for non-idle states, macOS renders
/// the actual color in the menu bar.
///
/// States:
///   • idle       → system default (template mic, adapts to menu bar appearance)
///   • recording  → red filled mic (non-template, colored)
///   • processing → orange spinner (non-template, colored)
///   • error      → yellow warning (non-template, colored)
struct MenuBarIcon: View {
    let appStatus: AppStatus
    let audioLevel: Float

    var body: some View {
        Image(nsImage: makeMenuBarIcon())
    }

    private func makeMenuBarIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        guard let baseImage = NSImage(systemSymbolName: iconName, accessibilityDescription: "VocaMac")?
            .withSymbolConfiguration(config) else {
            // Fallback to a basic mic if symbol lookup fails
            return NSImage(systemSymbolName: "mic", accessibilityDescription: "VocaMac") ?? NSImage()
        }

        // Tint the icon with the status color
        let tintColor = nsColor
        let size = baseImage.size

        let tinted = NSImage(size: size, flipped: false) { rect in
            baseImage.draw(in: rect)
            tintColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private var iconName: String {
        switch appStatus {
        case .idle:
            return "mic.fill"
        case .recording:
            return "mic.fill"
        case .processing:
            return "ellipsis.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var nsColor: NSColor {
        switch appStatus {
        case .idle:       return NSColor(red: 0, green: 0.478, blue: 1.0, alpha: 1.0)
        case .recording:  return .systemRed
        case .processing: return NSColor(red: 0.749, green: 0.353, blue: 0.949, alpha: 1.0) // #BF5AF2
        case .error:      return .systemYellow
        }
    }
}

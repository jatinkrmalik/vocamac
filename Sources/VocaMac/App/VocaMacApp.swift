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

@main
struct VocaMacApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsManager = SettingsWindowManager()

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

/// Renders the Circle Mic icon in the menu bar based on app status.
/// Draws a custom mic-in-circle shape that matches the VocaMac branding
/// (Logo #4 — "Circle Mic") instead of a generic SF Symbol.
struct MenuBarIcon: View {
    let appStatus: AppStatus
    let audioLevel: Float

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2
            let cy = size.height / 2

            // Scale factor from the 512-unit design coordinate space
            let scale = s / 512.0

            // --- Circle outline (subtle) ---
            let circleRect = CGRect(
                x: cx - 140 * scale,
                y: cy - 140 * scale,
                width: 280 * scale,
                height: 280 * scale
            )
            var circlePath = Path()
            circlePath.addEllipse(in: circleRect)
            context.stroke(circlePath, with: .color(iconColor.opacity(0.25)), lineWidth: 1.2)

            // --- Microphone capsule (rounded rect) ---
            let capsuleW = 56.0 * scale
            let capsuleH = 100.0 * scale
            let capsuleRect = CGRect(
                x: cx - capsuleW / 2,
                y: cy - 88 * scale,
                width: capsuleW,
                height: capsuleH
            )
            let capsulePath = Path(roundedRect: capsuleRect, cornerRadius: 28 * scale)
            context.fill(capsulePath, with: .color(iconColor))

            // --- Mic cradle arc ---
            var cradlePath = Path()
            let cradleY = cy + 4 * scale
            let cradleRadius = 50.0 * scale
            cradlePath.addArc(
                center: CGPoint(x: cx, y: cradleY),
                radius: cradleRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(180),
                clockwise: false
            )
            context.stroke(
                cradlePath,
                with: .color(iconColor),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )

            // --- Stem ---
            var stemPath = Path()
            stemPath.move(to: CGPoint(x: cx, y: cradleY + cradleRadius))
            stemPath.addLine(to: CGPoint(x: cx, y: cradleY + cradleRadius + 28 * scale))
            context.stroke(
                stemPath,
                with: .color(iconColor),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )

            // --- Base ---
            var basePath = Path()
            let baseY = cradleY + cradleRadius + 28 * scale
            basePath.move(to: CGPoint(x: cx - 22 * scale, y: baseY))
            basePath.addLine(to: CGPoint(x: cx + 22 * scale, y: baseY))
            context.stroke(
                basePath,
                with: .color(iconColor),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
        }
        .frame(width: 18, height: 18)
    }

    private var iconColor: Color {
        switch appStatus {
        case .idle:       return .primary
        case .recording:  return .red
        case .processing: return .orange
        case .error:      return .yellow
        }
    }
}

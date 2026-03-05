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
/// Creates an NSImage-based template icon that matches the VocaMac branding
/// (Logo #4 — "Circle Mic"). Uses NSImage so it works with MenuBarExtra's label.
struct MenuBarIcon: View {
    let appStatus: AppStatus
    let audioLevel: Float

    var body: some View {
        Image(nsImage: makeMenuBarImage())
            .foregroundStyle(iconColor)
    }

    /// Draws the Circle Mic icon into an NSImage suitable for the menu bar.
    /// The image is set as a template so macOS handles light/dark appearance,
    /// except when a specific status color override is applied.
    private func makeMenuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let s = min(rect.width, rect.height)
            let cx = rect.width / 2
            let cy = rect.height / 2
            let scale = s / 512.0

            // Use black for template rendering — macOS will tint it
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // --- Circle outline (subtle) ---
            let circleRect = NSRect(
                x: cx - 140 * scale,
                y: cy - 140 * scale,
                width: 280 * scale,
                height: 280 * scale
            )
            let circlePath = NSBezierPath(ovalIn: circleRect)
            circlePath.lineWidth = 1.0
            NSColor.black.withAlphaComponent(0.3).setStroke()
            circlePath.stroke()

            // Reset stroke color to full black
            NSColor.black.setStroke()

            // --- Microphone capsule (rounded rect) ---
            let capsuleW = 56.0 * scale
            let capsuleH = 100.0 * scale
            let capsuleRect = NSRect(
                x: cx - capsuleW / 2,
                y: cy - capsuleH / 2 + 20 * scale,
                width: capsuleW,
                height: capsuleH
            )
            let capsulePath = NSBezierPath(roundedRect: capsuleRect, xRadius: 28 * scale, yRadius: 28 * scale)
            capsulePath.fill()

            // --- Mic cradle arc ---
            let cradleCenterY = cy - 28 * scale
            let cradleRadius = 50.0 * scale
            let cradlePath = NSBezierPath()
            cradlePath.appendArc(
                withCenter: NSPoint(x: cx, y: cradleCenterY),
                radius: cradleRadius,
                startAngle: 180,
                endAngle: 0,
                clockwise: true
            )
            cradlePath.lineWidth = 1.2
            cradlePath.lineCapStyle = .round
            cradlePath.stroke()

            // --- Stem ---
            let stemPath = NSBezierPath()
            let stemTop = cradleCenterY - cradleRadius
            let stemBottom = stemTop - 28 * scale
            stemPath.move(to: NSPoint(x: cx, y: stemTop))
            stemPath.line(to: NSPoint(x: cx, y: stemBottom))
            stemPath.lineWidth = 1.2
            stemPath.lineCapStyle = .round
            stemPath.stroke()

            // --- Base ---
            let basePath = NSBezierPath()
            basePath.move(to: NSPoint(x: cx - 22 * scale, y: stemBottom))
            basePath.line(to: NSPoint(x: cx + 22 * scale, y: stemBottom))
            basePath.lineWidth = 1.2
            basePath.lineCapStyle = .round
            basePath.stroke()

            return true
        }
        image.isTemplate = (appStatus == .idle)
        return image
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

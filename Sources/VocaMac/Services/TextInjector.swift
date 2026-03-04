// TextInjector.swift
// VocaMac
//
// Injects transcribed text at the cursor position in any application
// using the clipboard (NSPasteboard) + simulated Cmd+V keystroke approach.

import Foundation
import AppKit

final class TextInjector {

    // MARK: - Constants

    /// Delay before restoring clipboard (seconds)
    private let clipboardRestoreDelay: Double = 2.0

    /// Virtual key code for the V key
    private let kVK_V: CGKeyCode = 9

    // MARK: - Public API

    /// Inject text at the current cursor position in any application
    /// - Parameters:
    ///   - text: The text to inject
    ///   - preserveClipboard: Whether to save and restore the clipboard contents
    func inject(text: String, preserveClipboard: Bool = true) {
        guard !text.isEmpty else { return }

        // Check accessibility permission
        let trusted = AXIsProcessTrusted()
        NSLog("[TextInjector] AXIsProcessTrusted = %@", trusted ? "YES" : "NO")

        if !trusted {
            NSLog("[TextInjector] No accessibility permission. Copying to clipboard only.")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }

        let pasteboard = NSPasteboard.general

        // Save current clipboard text
        let previousText = preserveClipboard ? pasteboard.string(forType: .string) : nil

        // Set transcribed text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSLog("[TextInjector] Set clipboard: '%@'", String(text.prefix(80)))

        // Delay to let clipboard settle, then simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            NSLog("[TextInjector] Simulating Cmd+V...")
            simulatePaste()

            // Restore clipboard after paste completes
            if preserveClipboard, let previous = previousText {
                DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    // MARK: - Paste Simulation

    /// Simulate Cmd+V keystroke to paste from clipboard
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd+V key down
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_V, keyDown: true) else {
            NSLog("[TextInjector] ERROR: Failed to create key down event")
            return
        }
        keyDown.flags = [.maskCommand]
        keyDown.post(tap: .cgAnnotatedSessionEventTap)

        // Cmd+V key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_V, keyDown: false) else {
            NSLog("[TextInjector] ERROR: Failed to create key up event")
            return
        }
        keyUp.flags = [.maskCommand]
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        NSLog("[TextInjector] Cmd+V posted")
    }
}

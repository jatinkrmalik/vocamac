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

    // MARK: - Types

    /// Deep copy of a single pasteboard item's data across all its types
    private struct PasteboardItemSnapshot {
        /// Map from pasteboard type to raw data
        let dataByType: [(NSPasteboard.PasteboardType, Data)]
    }

    /// Deep copy of the entire pasteboard state
    private struct PasteboardSnapshot {
        let items: [PasteboardItemSnapshot]
    }

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

        // Deep-copy current clipboard state before we overwrite it.
        // NSPasteboardItem objects are invalidated when the pasteboard is cleared,
        // so we must extract the raw data eagerly.
        let snapshot = preserveClipboard ? captureSnapshot(pasteboard) : nil

        // Set transcribed text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSLog("[TextInjector] Set clipboard: '%@'", String(text.prefix(80)))

        // Delay to let clipboard settle, then simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            NSLog("[TextInjector] Simulating Cmd+V...")
            simulatePaste()

            // Restore clipboard after paste completes
            if preserveClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
                    if let snapshot = snapshot {
                        self.restoreSnapshot(snapshot, to: pasteboard)
                    } else {
                        // Previous clipboard was empty; clear the transcribed text
                        pasteboard.clearContents()
                    }
                    NSLog("[TextInjector] Clipboard restored")
                }
            }
        }
    }

    // MARK: - Clipboard Snapshot Management

    /// Deep-copy every item and type from the pasteboard into plain `Data` values.
    /// This must be called *before* `clearContents()` because NSPasteboardItem
    /// objects are invalidated when the pasteboard changes.
    private func captureSnapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return nil
        }

        var itemSnapshots: [PasteboardItemSnapshot] = []

        for item in pasteboardItems {
            var dataByType: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType.append((type, data))
                }
            }
            if !dataByType.isEmpty {
                itemSnapshots.append(PasteboardItemSnapshot(dataByType: dataByType))
            }
        }

        guard !itemSnapshots.isEmpty else { return nil }
        return PasteboardSnapshot(items: itemSnapshots)
    }

    /// Write a previously captured snapshot back to the pasteboard.
    private func restoreSnapshot(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        var newItems: [NSPasteboardItem] = []
        for itemSnapshot in snapshot.items {
            let newItem = NSPasteboardItem()
            for (type, data) in itemSnapshot.dataByType {
                newItem.setData(data, forType: type)
            }
            newItems.append(newItem)
        }

        pasteboard.writeObjects(newItems)
        NSLog("[TextInjector] Restored clipboard with %ld items", newItems.count)
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

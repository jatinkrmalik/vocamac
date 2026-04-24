// TextInjector.swift
// VocaMac
//
// Injects transcribed text at the cursor position in any application
// using the clipboard (NSPasteboard) + simulated Cmd+V keystroke approach.

import Foundation
import AppKit
import Carbon.HIToolbox

final class TextInjector {

    // MARK: - Constants

    /// Delay after simulating Cmd+V before restoring the clipboard.
    /// This must be long enough for the target application to read the
    /// pasteboard in response to the paste event. 50 ms is sufficient
    /// for all mainstream macOS apps (most read the pasteboard
    /// synchronously on the main thread).
    private let clipboardRestoreDelay: Double = 0.05

    /// Delay before simulating the Cmd+V keystroke, giving the
    /// pasteboard a moment to settle after we write to it.
    private let prePasteDelay: Double = 0.05

    /// Default virtual key code for the V key on a US-QWERTY layout.
    /// Used as a fallback when the active layout cannot be inspected.
    private let kVK_ANSI_V_Fallback: CGKeyCode = 9

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
        VocaLogger.debug(.textInjector, "AXIsProcessTrusted = \(trusted ? "YES" : "NO")")

        if !trusted {
            VocaLogger.warning(.textInjector, "No accessibility permission. Copying to clipboard only.")
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
        VocaLogger.debug(.textInjector, "Set clipboard: '\(String(text.prefix(80)))'")

        // Record the changeCount right after we write the transcribed text.
        // We check this before restoring so we don't clobber a newer clipboard
        // entry if the user (or another app) copies something in the meantime.
        let changeCountAfterWrite = pasteboard.changeCount

        // Delay to let clipboard settle, then simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + prePasteDelay) { [self] in
            VocaLogger.debug(.textInjector, "Simulating Cmd+V...")
            simulatePaste()

            // Restore clipboard as soon as the paste event has been dispatched.
            // The short delay gives the target app time to read the pasteboard.
            if preserveClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
                    // Guard: only restore if the pasteboard hasn't been modified
                    // by the user or another app since we wrote the transcribed text.
                    guard pasteboard.changeCount == changeCountAfterWrite else {
                        VocaLogger.debug(.textInjector, "Clipboard was modified externally — skipping restore")
                        return
                    }

                    if let snapshot = snapshot {
                        self.restoreSnapshot(snapshot, to: pasteboard)
                    } else {
                        // Previous clipboard was empty; clear the transcribed text
                        pasteboard.clearContents()
                    }
                    VocaLogger.debug(.textInjector, "Clipboard restored")
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
        VocaLogger.debug(.textInjector, "Restored clipboard with \(newItems.count) items")
    }

    // MARK: - Paste Simulation

    /// Simulate Cmd+V keystroke to paste from clipboard.
    ///
    /// On non-QWERTY layouts (e.g. Dvorak, Colemak, AZERTY), the hardware
    /// virtual keycode for "V" on a US-QWERTY keyboard (9) maps to a
    /// different character. Posting `kVK_ANSI_V` directly therefore triggers
    /// the wrong shortcut — for example, on Dvorak keycode 9 produces ".",
    /// so the system fires Cmd+. (which most apps interpret as "cancel")
    /// instead of Cmd+V (paste). See GitHub issue #123.
    ///
    /// To fix this, we resolve the keycode that produces the character "v"
    /// on the *currently active* keyboard layout and post that keycode
    /// instead. If the active layout cannot be inspected (e.g. in tests
    /// with no input source available) we fall back to the QWERTY keycode.
    private func simulatePaste() {
        let keyCode = TextInjector.keyCode(forCharacter: "v") ?? kVK_ANSI_V_Fallback
        VocaLogger.debug(.textInjector, "Resolved keycode for 'v' on active layout: \(keyCode)")

        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd+V key down
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            VocaLogger.error(.textInjector, "ERROR: Failed to create key down event")
            return
        }
        keyDown.flags = [.maskCommand]
        keyDown.post(tap: .cgAnnotatedSessionEventTap)

        // Cmd+V key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            VocaLogger.error(.textInjector, "ERROR: Failed to create key up event")
            return
        }
        keyUp.flags = [.maskCommand]
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        VocaLogger.info(.textInjector, "Cmd+V posted (keycode \(keyCode))")
    }

    // MARK: - Keyboard Layout Resolution

    /// Find the virtual keycode that produces the given character on the
    /// currently active keyboard layout.
    ///
    /// This walks all keycodes in the standard ANSI range (0...127) and
    /// translates each one through the active Unicode key layout using
    /// `UCKeyTranslate`, returning the first keycode whose unmodified
    /// output matches the requested character.
    ///
    /// - Parameter character: The character to look up (e.g. "v")
    /// - Returns: The virtual keycode that produces the character on the
    ///            active layout, or `nil` if the character is unreachable
    ///            or the input source cannot be inspected.
    static func keyCode(forCharacter character: Character) -> CGKeyCode? {
        // Prefer the active ASCII-capable input source; this skips over
        // non-Latin layouts like Hiragana where "v" is not directly
        // typable, and falls back to the underlying ASCII layout that
        // macOS uses for shortcut interpretation.
        let inputSource: TISInputSource? = {
            if let asciiSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
                return asciiSource
            }
            return TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        }()

        guard let source = inputSource else { return nil }

        guard let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data

        let target = String(character)

        return layoutData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> CGKeyCode? in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            let keyboardLayout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)

            var deadKeyState: UInt32 = 0
            let maxStringLength = 4
            var actualStringLength = 0
            var unicodeString = [UniChar](repeating: 0, count: maxStringLength)

            for keyCode in 0..<128 {
                deadKeyState = 0
                let status = UCKeyTranslate(
                    keyboardLayout,
                    UInt16(keyCode),
                    UInt16(kUCKeyActionDisplay),
                    0, // no modifiers — match the bare key
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    maxStringLength,
                    &actualStringLength,
                    &unicodeString
                )

                guard status == noErr, actualStringLength > 0 else { continue }

                let produced = String(utf16CodeUnits: unicodeString, count: actualStringLength)
                if produced == target {
                    return CGKeyCode(keyCode)
                }
            }

            return nil
        }
    }
}

// MARK: - TextInjecting Conformance

extension TextInjector: TextInjecting {}

// HotKeyManager.swift
// VocaMac
//
// Listens for global hotkey events using CGEventTap.
// Supports push-to-talk (hold key) and double-tap toggle modes.

import Foundation
import AppKit

final class HotKeyManager {

    // MARK: - Properties

    /// Event tap Mach port
    private var eventTap: CFMachPort?

    /// Run loop source for the event tap
    private var runLoopSource: CFRunLoopSource?

    /// Whether the event tap is currently active
    private(set) var isListening = false

    /// The key code to listen for
    private var targetKeyCode: Int = 61  // Right Option

    /// Current activation mode
    private var mode: ActivationMode = .pushToTalk

    /// Double-tap threshold in seconds
    private var doubleTapThreshold: Double = 0.4

    /// Timestamp of the last key down event for the target key
    private var lastKeyDownTime: CFAbsoluteTime = 0

    /// Whether the key is currently held down (for push-to-talk)
    private var isKeyHeld = false

    /// Whether we are currently in a "recording" toggle state (for double-tap mode)
    private var isToggled = false

    // MARK: - Callbacks

    /// Called when recording should start
    var onRecordingStart: (() -> Void)?

    /// Called when recording should stop
    var onRecordingStop: (() -> Void)?

    // MARK: - Accessibility Permission

    /// Check if the app has Accessibility permission
    /// - Parameter prompt: Whether to show the system prompt if not trusted
    /// - Returns: true if the app is trusted for Accessibility
    static func checkAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Lifecycle

    /// Start listening for global hotkey events
    /// - Parameters:
    ///   - keyCode: The virtual key code to listen for (default: 61 = Right Option)
    ///   - mode: The activation mode (push-to-talk or double-tap toggle)
    ///   - doubleTapThreshold: Time window for double-tap detection (seconds)
    func startListening(
        keyCode: Int = 61,
        mode: ActivationMode = .pushToTalk,
        doubleTapThreshold: Double = 0.4
    ) {
        guard !isListening else {
            print("[HotKeyManager] Already listening")
            return
        }

        self.targetKeyCode = keyCode
        self.mode = mode
        self.doubleTapThreshold = doubleTapThreshold
        self.lastKeyDownTime = 0
        self.isKeyHeld = false
        self.isToggled = false

        // Create event tap for key events and flags changed (modifier keys)
        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        // We need to pass `self` as a raw pointer to the C callback
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,  // Listen only — don't suppress events
            eventsOfInterest: eventMask,
            callback: HotKeyManager.eventTapCallback,
            userInfo: userInfo
        ) else {
            NSLog("[HotKeyManager] FAILED to create event tap! Check Accessibility & Input Monitoring permissions.")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isListening = true
        NSLog("[HotKeyManager] Event tap created successfully. Listening for keyCode %d in %@ mode", keyCode, mode.rawValue)
    }

    /// Stop listening for global hotkey events
    func stopListening() {
        guard isListening else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isListening = false
        isKeyHeld = false
        isToggled = false

        print("[HotKeyManager] Stopped listening")
    }

    /// Update the configuration while listening
    func updateConfiguration(
        keyCode: Int? = nil,
        mode: ActivationMode? = nil,
        doubleTapThreshold: Double? = nil
    ) {
        if let keyCode = keyCode { self.targetKeyCode = keyCode }
        if let mode = mode { self.mode = mode }
        if let threshold = doubleTapThreshold { self.doubleTapThreshold = threshold }
    }

    // MARK: - Event Tap Callback

    /// Static C callback for CGEventTap — dispatches to the instance method
    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }

        let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()

        // Handle tap being disabled (system can disable taps if they're too slow)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        manager.handleEvent(type: type, event: event)

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Event Handling

    /// Handle an incoming key event
    private func handleEvent(type: CGEventType, event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // For modifier keys (like Option), we use flagsChanged events
        // For regular keys, we use keyDown/keyUp events
        if type == .flagsChanged {
            if keyCode == targetKeyCode {
                NSLog("[HotKeyManager] flagsChanged event for target keyCode %d", keyCode)
            }
            handleModifierKeyEvent(keyCode: keyCode, event: event)
        } else if type == .keyDown || type == .keyUp {
            handleRegularKeyEvent(keyCode: keyCode, isKeyDown: type == .keyDown)
        }
    }

    /// Handle modifier key events (Option, Command, Control, Shift, Fn)
    /// Modifier keys generate flagsChanged events, not keyDown/keyUp
    private func handleModifierKeyEvent(keyCode: Int, event: CGEvent) {
        guard keyCode == targetKeyCode else { return }

        // Determine if the key is pressed or released by checking modifier flags
        let flags = event.flags

        // Map key codes to their corresponding flag masks
        let isPressed: Bool
        switch keyCode {
        case 61, 58:  // Right Option (61) or Left Option (58)
            isPressed = flags.contains(.maskAlternate)
        case 54, 55:  // Right Command (54) or Left Command (55)
            isPressed = flags.contains(.maskCommand)
        case 60, 56:  // Right Shift (60) or Left Shift (56)
            isPressed = flags.contains(.maskShift)
        case 62, 59:  // Right Control (62) or Left Control (59)
            isPressed = flags.contains(.maskControl)
        case 63:      // Fn key
            isPressed = flags.contains(.maskSecondaryFn)
        default:
            return
        }

        if isPressed {
            handleKeyDown()
        } else {
            handleKeyUp()
        }
    }

    /// Handle regular (non-modifier) key events
    private func handleRegularKeyEvent(keyCode: Int, isKeyDown: Bool) {
        guard keyCode == targetKeyCode else { return }

        if isKeyDown {
            handleKeyDown()
        } else {
            handleKeyUp()
        }
    }

    /// Process a key-down event for the target hotkey
    private func handleKeyDown() {
        let currentTime = CFAbsoluteTimeGetCurrent()
        NSLog("[HotKeyManager] Key DOWN detected (mode=%@)", mode.rawValue)

        switch mode {
        case .pushToTalk:
            // Push-to-talk: start recording on key down (if not already held)
            if !isKeyHeld {
                isKeyHeld = true
                NSLog("[HotKeyManager] Push-to-talk: START recording")
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStart?()
                }
            }

        case .doubleTapToggle:
            // Double-tap: check if this is the second tap within threshold
            let timeSinceLastTap = currentTime - lastKeyDownTime

            if timeSinceLastTap < doubleTapThreshold && timeSinceLastTap > 0.05 {
                // This is a double-tap!
                isToggled.toggle()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.isToggled {
                        self.onRecordingStart?()
                    } else {
                        self.onRecordingStop?()
                    }
                }
                // Reset to avoid triple-tap triggering
                lastKeyDownTime = 0
            } else {
                lastKeyDownTime = currentTime
            }
        }
    }

    /// Process a key-up event for the target hotkey
    private func handleKeyUp() {
        NSLog("[HotKeyManager] Key UP detected (mode=%@)", mode.rawValue)

        switch mode {
        case .pushToTalk:
            // Push-to-talk: stop recording on key release
            if isKeyHeld {
                isKeyHeld = false
                NSLog("[HotKeyManager] Push-to-talk: STOP recording")
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStop?()
                }
            }

        case .doubleTapToggle:
            // No action on key up for toggle mode
            break
        }
    }

    // MARK: - Deinit

    deinit {
        stopListening()
    }
}

// MARK: - Common Key Codes Reference

/// Reference for common macOS virtual key codes
/// Used for hotkey configuration UI
enum KeyCodeReference {
    static let commonHotKeys: [(name: String, keyCode: Int)] = [
        ("Right Option (⌥)", 61),
        ("Left Option (⌥)", 58),
        ("Right Command (⌘)", 54),
        ("Right Shift (⇧)", 60),
        ("Right Control (⌃)", 62),
        ("Fn", 63),
        ("F5", 96),
        ("F6", 97),
        ("F7", 98),
        ("F8", 100),
        ("F9", 101),
        ("F10", 109),
        ("F11", 103),
        ("F12", 111),
    ]

    /// Get the display name for a key code
    static func displayName(for keyCode: Int) -> String {
        commonHotKeys.first(where: { $0.keyCode == keyCode })?.name ?? "Key \(keyCode)"
    }
}

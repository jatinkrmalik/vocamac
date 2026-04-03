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
    private(set) var eventTap: CFMachPort?

    /// Public accessor for permission checking
    var activeEventTap: CFMachPort? { eventTap }

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

    /// Safety timer that auto-fires key-up if a real key-up event is missed.
    /// macOS can drop flagsChanged events when multiple modifiers interact,
    /// leaving push-to-talk stuck in the "recording" state.
    private var keyHeldSafetyTimer: DispatchWorkItem?

    /// Maximum duration (seconds) before the safety timer forces a key-up.
    /// Set via `startListening(safetyTimeout:)` — should match (or slightly
    /// exceed) the app's max recording duration so the safety timer acts as
    /// a last-resort backstop *after* AudioEngine's own max-duration callback
    /// has had a chance to fire.
    private var safetyTimeoutSeconds: Double = 65.0

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
    ///   - safetyTimeout: Maximum seconds before the safety timer forces a key-up
    ///     in push-to-talk mode. Should be slightly longer than the app's max
    ///     recording duration so AudioEngine's own limit fires first. The safety
    ///     timer is a last-resort backstop for when a key-up event is lost entirely.
    func startListening(
        keyCode: Int = 61,
        mode: ActivationMode = .pushToTalk,
        doubleTapThreshold: Double = 0.4,
        safetyTimeout: Double = 65.0
    ) {
        guard !isListening else {
            VocaLogger.debug(.hotKeyManager, "Already listening")
            return
        }

        self.targetKeyCode = keyCode
        self.mode = mode
        self.doubleTapThreshold = doubleTapThreshold
        self.safetyTimeoutSeconds = safetyTimeout
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
            VocaLogger.error(.hotKeyManager, "FAILED to create event tap! Check Accessibility & Input Monitoring permissions.")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isListening = true
        VocaLogger.info(.hotKeyManager, "Event tap created successfully. Listening for keyCode \(keyCode) in \(mode.rawValue) mode")
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
        previousFlags = []
        cancelSafetyTimer()

        VocaLogger.info(.hotKeyManager, "Stopped listening")
    }

    /// Reset internal key tracking state without stopping the listener.
    /// Used when the app forcibly recovers from a stuck recording state
    /// (e.g., after an audio device change) so that the next keypress
    /// is treated as a fresh key-down rather than a recovery key-down.
    func resetKeyState() {
        isKeyHeld = false
        isToggled = false
        cancelSafetyTimer()
        VocaLogger.debug(.hotKeyManager, "Key state reset")
    }

    /// Update the configuration while listening
    /// - Parameters:
    ///   - keyCode: New key code to listen for
    ///   - mode: New activation mode
    ///   - doubleTapThreshold: New double-tap detection window (seconds)
    ///   - safetyTimeout: New safety timer duration (seconds). Should be
    ///     `maxRecordingDuration + 5` to act as a backstop after AudioEngine's
    ///     own max-duration callback.
    func updateConfiguration(
        keyCode: Int? = nil,
        mode: ActivationMode? = nil,
        doubleTapThreshold: Double? = nil,
        safetyTimeout: Double? = nil
    ) {
        if let keyCode = keyCode { self.targetKeyCode = keyCode }
        if let mode = mode { self.mode = mode }
        if let threshold = doubleTapThreshold { self.doubleTapThreshold = threshold }
        if let timeout = safetyTimeout { self.safetyTimeoutSeconds = timeout }
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
                VocaLogger.debug(.hotKeyManager, "flagsChanged event for target keyCode \(keyCode)")
            }
            handleModifierKeyEvent(keyCode: keyCode, event: event)
        } else if type == .keyDown || type == .keyUp {
            handleRegularKeyEvent(keyCode: keyCode, isKeyDown: type == .keyDown)
        }
    }

    /// Handle modifier key events (Option, Command, Control, Shift, Fn)
    /// Modifier keys generate flagsChanged events, not keyDown/keyUp.
    ///
    /// **Key insight:** Modifier flags like `.maskAlternate` are shared between
    /// left and right variants (e.g., Left Option and Right Option both set
    /// `.maskAlternate`). A `flagsChanged` event fires whenever *any* modifier
    /// changes, so we can't simply check the flag — pressing Left Option while
    /// Right Option is already held would still show `.maskAlternate` as set,
    /// and releasing Right Option while Left Option is held would *not* clear
    /// the flag, causing the key-up to be missed.
    ///
    /// **Fix:** We track the raw flags value and detect transitions. When the
    /// target key code fires a `flagsChanged` event, we compare the current
    /// flags with the previous snapshot to determine if the *specific* key
    /// was pressed or released.
    private var previousFlags: CGEventFlags = []

    private func handleModifierKeyEvent(keyCode: Int, event: CGEvent) {
        guard keyCode == targetKeyCode else { return }

        let flags = event.flags

        // The flag mask that corresponds to this key's modifier group
        let relevantMask: CGEventFlags
        switch keyCode {
        case 61, 58:  // Right Option (61) or Left Option (58)
            relevantMask = .maskAlternate
        case 54, 55:  // Right Command (54) or Left Command (55)
            relevantMask = .maskCommand
        case 60, 56:  // Right Shift (60) or Left Shift (56)
            relevantMask = .maskShift
        case 62, 59:  // Right Control (62) or Left Control (59)
            relevantMask = .maskControl
        case 63:      // Fn key
            relevantMask = .maskSecondaryFn
        default:
            return
        }

        // A flagsChanged event for this keyCode means the key was either
        // pressed or released. We determine which by comparing the flag
        // state with our expectation:
        //
        // • If the modifier flag is set AND we weren't already tracking
        //   this key as held → key was pressed.
        // • If the modifier flag is cleared → key was definitely released.
        // • If the modifier flag is still set BUT macOS sent a flagsChanged
        //   event specifically for our keyCode → the *specific* physical key
        //   changed state. Since a flagsChanged for keyCode X only fires when
        //   key X changes, if we were already holding it, this means it was
        //   released (the flag may still be set because the *other* key in
        //   the pair, e.g. Left Option, is still down).
        let flagIsSet = flags.contains(relevantMask)

        let isPressed: Bool
        if !flagIsSet {
            // Flag is clear — the key is definitely released
            isPressed = false
        } else if !isKeyHeld {
            // Flag is set and we weren't tracking this key — it was pressed
            isPressed = true
        } else {
            // Flag is still set but we're already tracking the key as held,
            // and macOS sent a flagsChanged event for this exact keyCode.
            // This means the physical key was released (the flag persists
            // because another key in the same modifier group is still held).
            isPressed = false
        }

        previousFlags = flags

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
        VocaLogger.debug(.hotKeyManager, "Key DOWN detected (mode=\(mode.rawValue))")

        switch mode {
        case .pushToTalk:
            if !isKeyHeld {
                // Normal case: start recording on key down
                isKeyHeld = true
                VocaLogger.debug(.hotKeyManager, "Push-to-talk: START recording")
                startSafetyTimer()
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStart?()
                }
            } else {
                // Recovery: key-down while already held means the previous
                // key-up was missed (macOS dropped the flagsChanged event).
                // Treat this as a stop → the user is pressing the key again
                // because recording is stuck.
                VocaLogger.warning(.hotKeyManager, "Push-to-talk: key DOWN while already held — forcing STOP (recovery)")
                isKeyHeld = false
                cancelSafetyTimer()
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStop?()
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
        VocaLogger.debug(.hotKeyManager, "Key UP detected (mode=\(mode.rawValue))")

        switch mode {
        case .pushToTalk:
            // Push-to-talk: stop recording on key release
            if isKeyHeld {
                isKeyHeld = false
                cancelSafetyTimer()
                VocaLogger.debug(.hotKeyManager, "Push-to-talk: STOP recording")
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStop?()
                }
            }

        case .doubleTapToggle:
            // No action on key up for toggle mode
            break
        }
    }

    // MARK: - Safety Timer

    /// Start a safety timer that forces a key-up if the real event is never received.
    /// This prevents the app from getting stuck in a "recording" state indefinitely.
    ///
    /// The timeout is set via `startListening(safetyTimeout:)` and should be
    /// slightly longer than `maxRecordingDuration` so that AudioEngine's own
    /// max-duration callback fires first under normal conditions. The safety
    /// timer only kicks in when a key-up event is completely lost.
    private func startSafetyTimer() {
        cancelSafetyTimer()

        let timeout = safetyTimeoutSeconds
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isKeyHeld else { return }
            VocaLogger.warning(.hotKeyManager, "Safety timer fired — forcing key-up (key held for >\(timeout)s)")
            self.isKeyHeld = false
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStop?()
            }
        }
        keyHeldSafetyTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    /// Cancel the safety timer (called on normal key-up)
    private func cancelSafetyTimer() {
        keyHeldSafetyTimer?.cancel()
        keyHeldSafetyTimer = nil
    }

    // MARK: - Event Tap Health Check

    /// Check whether the event tap is still healthy.
    /// macOS can silently disable event taps (e.g., after sleep/wake, permission
    /// changes, or system resource pressure). If we detect a disabled tap, we
    /// attempt to re-enable it. Returns `true` if the tap is healthy.
    ///
    /// Call this periodically (e.g., from a timer in AppState) to catch cases
    /// where the tap dies without triggering the `tapDisabledByTimeout` callback
    /// (which only fires when an event arrives — if no events arrive, the
    /// callback never runs and the tap stays dead).
    func checkAndRepairEventTap() -> Bool {
        guard isListening, let tap = eventTap else {
            // Not listening or no tap — not healthy
            return false
        }

        if CGEvent.tapIsEnabled(tap: tap) {
            return true
        }

        // Tap exists but is disabled — try to re-enable it
        VocaLogger.warning(.hotKeyManager, "Event tap was disabled by macOS — re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)

        // Verify re-enable worked
        let reEnabled = CGEvent.tapIsEnabled(tap: tap)
        if reEnabled {
            VocaLogger.info(.hotKeyManager, "Event tap re-enabled successfully")
        } else {
            VocaLogger.error(.hotKeyManager, "Failed to re-enable event tap — recreating")
            // Tear down and recreate the tap entirely
            stopListening()
            startListening(
                keyCode: targetKeyCode,
                mode: mode,
                doubleTapThreshold: doubleTapThreshold,
                safetyTimeout: safetyTimeoutSeconds
            )
        }

        return isListening
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

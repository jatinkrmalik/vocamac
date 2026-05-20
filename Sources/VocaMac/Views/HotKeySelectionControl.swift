// HotKeySelectionControl.swift
// VocaMac
//
// Reusable hotkey picker with direct key recording for settings and onboarding.

import AppKit
import SwiftUI

struct HotKeySelectionControl: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRecording = false
    @State private var wasListeningBeforeRecording = false

    let pickerLabel: String
    let footerText: String?

    init(pickerLabel: String = "Preset", footerText: String? = nil) {
        self.pickerLabel = pickerLabel
        self.footerText = footerText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(pickerLabel, selection: $appState.hotKeyCode) {
                    ForEach(KeyCodeReference.commonHotKeys, id: \.keyCode) { hotKey in
                        Text(hotKey.name).tag(hotKey.keyCode)
                    }

                    if !KeyCodeReference.isCommonHotKey(appState.hotKeyCode) {
                        Divider()
                        Text("Custom: \(KeyCodeReference.displayName(for: appState.hotKeyCode))")
                            .tag(appState.hotKeyCode)
                    }
                }
                .disabled(isRecording)
                .onChange(of: appState.hotKeyCode) { newCode in
                    guard !isRecording else { return }
                    appState.hotKeyManager.updateConfiguration(keyCode: newCode)
                }

                HotKeyRecorderButton(
                    isRecording: $isRecording,
                    onStart: beginRecording,
                    onCancel: finishRecording,
                    onKeyRecorded: recordKey
                )
            }

            if isRecording {
                Label("Press any single key", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            } else if let footerText {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            guard isRecording else { return }
            isRecording = false
            finishRecording()
        }
    }

    private func beginRecording() {
        wasListeningBeforeRecording = appState.hotKeyManager.isListening
        if wasListeningBeforeRecording {
            appState.hotKeyManager.stopListening()
        }
    }

    private func finishRecording() {
        if wasListeningBeforeRecording {
            restartHotKeyListener()
        }
        wasListeningBeforeRecording = false
    }

    private func recordKey(_ keyCode: Int) {
        appState.hotKeyCode = keyCode
        appState.hotKeyManager.updateConfiguration(keyCode: keyCode)
        finishRecording()
    }

    private func restartHotKeyListener() {
        appState.hotKeyManager.startListening(
            keyCode: appState.hotKeyCode,
            mode: appState.activationMode,
            doubleTapThreshold: appState.doubleTapThreshold,
            safetyTimeout: Double(appState.maxRecordingDuration) + 5.0
        )
    }
}

private struct HotKeyRecorderButton: View {
    @Binding var isRecording: Bool

    let onStart: () -> Void
    let onCancel: () -> Void
    let onKeyRecorded: (Int) -> Void

    var body: some View {
        ZStack {
            Button {
                if isRecording {
                    isRecording = false
                    onCancel()
                } else {
                    onStart()
                    isRecording = true
                }
            } label: {
                Label(isRecording ? "Cancel" : "Record", systemImage: isRecording ? "xmark.circle" : "record.circle")
            }
            .controlSize(.small)

            if isRecording {
                HotKeyCaptureView { keyCode in
                    isRecording = false
                    onKeyRecorded(keyCode)
                }
                .frame(width: 1, height: 1)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct HotKeyCaptureView: NSViewRepresentable {
    let onCapture: (Int) -> Void

    func makeNSView(context: Context) -> HotKeyCaptureNSView {
        let view = HotKeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: HotKeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.focus()
    }

    static func dismantleNSView(_ nsView: HotKeyCaptureNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class HotKeyCaptureNSView: NSView {
    var onCapture: ((Int) -> Void)?

    private var localMonitor: Any?
    private var didCapture = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor()
        focus()
    }

    override func keyDown(with event: NSEvent) {
        _ = capture(event)
    }

    override func flagsChanged(with event: NSEvent) {
        _ = capture(event)
    }

    func focus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func installMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            return self.capture(event) ? nil : event
        }
    }

    private func capture(_ event: NSEvent) -> Bool {
        guard !didCapture, shouldCapture(event) else { return false }

        didCapture = true
        stopMonitoring()

        let keyCode = Int(event.keyCode)
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(keyCode)
        }
        return true
    }

    private func shouldCapture(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            return !event.isARepeat
        case .flagsChanged:
            let keyCode = Int(event.keyCode)
            guard KeyCodeReference.isModifierKeyCode(keyCode),
                  let modifierFlag = modifierFlag(for: keyCode)
            else {
                return false
            }
            return event.modifierFlags.contains(modifierFlag)
        default:
            return false
        }
    }

    private func modifierFlag(for keyCode: Int) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55:
            return .command
        case 56, 60:
            return .shift
        case 58, 61:
            return .option
        case 59, 62:
            return .control
        case 63:
            return .function
        default:
            return nil
        }
    }

    deinit {
        stopMonitoring()
    }
}

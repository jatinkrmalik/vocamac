// MenuBarView.swift
// VocaMac
//
// The popover view shown when clicking the menu bar icon.
// Displays current status, audio level, last transcription, and quick actions.

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settingsManager: SettingsWindowManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            headerSection

            Divider()

            // Status & Recording
            statusSection

            // Last Transcription
            if let transcription = appState.lastTranscription {
                Divider()
                transcriptionSection(transcription)
            }

            // Permissions Warning
            if appState.micPermission != .granted || appState.accessibilityPermission != .granted {
                Divider()
                permissionsSection
            }

            Divider()

            // Quick Actions
            actionsSection
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text("VocaMac")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let model = appState.currentModel {
                    Text("Model: \(model.size.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if appState.whisperService.isModelLoaded {
                    Text("Model: \(appState.whisperService.loadedModelName ?? "Loaded")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Loading model...")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // RAM usage display
            Text(currentMemoryUsage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(statusText)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)

                Spacer()

                Text(activationModeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Audio level indicator (visible during recording)
            if appState.appStatus == .recording {
                AudioLevelView(level: appState.audioLevel)
                    .frame(height: 6)
            }

            // Processing indicator
            if appState.appStatus == .processing {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Transcription

    private func transcriptionSection(_ result: VocaTranscription) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last Transcription")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            Text(result.text)
                .font(.body)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

            HStack {
                Text("\(String(format: "%.1f", result.audioLengthSeconds))s audio")
                Text("•")
                Text("\(String(format: "%.1f", result.duration))s to transcribe")
                Text("•")
                Text(result.detectedLanguage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions Required")
                .font(.subheadline)
                .foregroundStyle(.orange)

            if appState.micPermission != .granted {
                Button {
                    appState.requestMicrophonePermission()
                } label: {
                    Label("Grant Microphone Access", systemImage: "mic.badge.xmark")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }

            if appState.accessibilityPermission != .granted {
                Button {
                    appState.requestAccessibilityPermission()
                } label: {
                    Label("Grant Accessibility Access", systemImage: "lock.shield")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)

                Text("Required for global hotkeys and text injection. Opens System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 2) {
            Button {
                settingsManager.open(appState: appState)
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                    Spacer()
                    Text("⌘,")
                        .foregroundStyle(.secondary)
                }
                .font(.body)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.0001))
                )
            }
            .buttonStyle(MenuRowButtonStyle())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit VocaMac")
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.secondary)
                }
                .font(.body)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.0001))
                )
            }
            .buttonStyle(MenuRowButtonStyle())
        }
        .padding(.horizontal, -8)
    }

    // MARK: - Helpers

    private var statusText: String {
        switch appState.appStatus {
        case .idle:       return "Ready"
        case .recording:  return "Recording..."
        case .processing: return "Transcribing..."
        case .error:      return appState.errorMessage ?? "Error"
        }
    }

    private var statusColor: Color {
        switch appState.appStatus {
        case .idle:       return .green
        case .recording:  return .red
        case .processing: return .orange
        case .error:      return .yellow
        }
    }

    private var activationModeHint: String {
        let keyName = KeyCodeReference.displayName(for: appState.hotKeyCode)
        switch appState.activationMode {
        case .pushToTalk:
            return "Hold \(keyName)"
        case .doubleTapToggle:
            return "Double-tap \(keyName)"
        }
    }

    /// Current app memory usage formatted as a human-readable string
    private var currentMemoryUsage: String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "— MB" }
        let mb = Double(info.resident_size) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Menu Row Button Style

/// A button style that highlights on hover, matching native macOS menu behavior.
struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Audio Level View

/// A simple horizontal bar that visualizes the current audio input level
struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))

                // Level indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(level)))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    private var levelColor: Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .orange }
        return .green
    }
}

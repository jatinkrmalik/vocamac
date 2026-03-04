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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("VocaMac")
                    .font(.headline)

                if let model = appState.currentModel {
                    Text("Model: \(model.size.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appState.whisperService.isModelLoaded {
                    Text("Model: \(appState.whisperService.loadedModelName ?? "Loaded")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Loading model...")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)

                Spacer()

                Text(activationModeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Audio level indicator (visible during recording)
            if appState.appStatus == .recording {
                AudioLevelView(level: appState.audioLevel)
                    .frame(height: 4)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last Transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            Text(result.text)
                .font(.callout)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

            HStack {
                Text("\(String(format: "%.1f", result.audioLengthSeconds))s audio")
                Text("•")
                Text("\(String(format: "%.1f", result.duration))s to transcribe")
                Text("•")
                Text(result.detectedLanguage)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions Required")
                .font(.caption)
                .foregroundStyle(.orange)

            if appState.micPermission != .granted {
                Button {
                    appState.requestMicrophonePermission()
                } label: {
                    Label("Grant Microphone Access", systemImage: "mic.badge.xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }

            if appState.accessibilityPermission != .granted {
                Button {
                    appState.requestAccessibilityPermission()
                } label: {
                    Label("Grant Accessibility Access", systemImage: "lock.shield")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)

                Text("Required for global hotkeys and text injection. Opens System Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 4) {
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
                .font(.callout)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            Divider()

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
                .font(.callout)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)
        }
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

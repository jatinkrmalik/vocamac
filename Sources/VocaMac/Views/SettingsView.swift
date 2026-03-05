// SettingsView.swift
// VocaMac
//
// Settings window for VocaMac configuration.
// Organized into tabs: General, Models, Audio, About.

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ModelSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "brain")
                }

            AudioSettingsTab()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            // Activation Mode
            Section("Activation Mode") {
                Picker("Mode", selection: $appState.activationMode) {
                    ForEach(ActivationMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.activationMode) { newMode in
                    appState.hotKeyManager.updateConfiguration(mode: newMode)
                }

                Text(appState.activationMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Hotkey
            Section("Hotkey") {
                Picker("Activation Key", selection: $appState.hotKeyCode) {
                    ForEach(KeyCodeReference.commonHotKeys, id: \.keyCode) { hotKey in
                        Text(hotKey.name).tag(hotKey.keyCode)
                    }
                }
                .onChange(of: appState.hotKeyCode) { newCode in
                    appState.hotKeyManager.updateConfiguration(keyCode: newCode)
                }

                if appState.activationMode == .doubleTapToggle {
                    HStack {
                        Text("Double-tap speed")
                        Slider(
                            value: $appState.doubleTapThreshold,
                            in: 0.2...0.8,
                            step: 0.05
                        )
                        Text("\(String(format: "%.2f", appState.doubleTapThreshold))s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    .onChange(of: appState.doubleTapThreshold) { newVal in
                        appState.hotKeyManager.updateConfiguration(doubleTapThreshold: newVal)
                    }

                    Text("Shorter = faster double-tap required. Longer = more forgiving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Language
            Section("Transcription Language") {
                Picker("Language", selection: $appState.selectedLanguage) {
                    Text("Auto-detect").tag("auto")
                    Divider()
                    Group {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Italian").tag("it")
                        Text("Portuguese").tag("pt")
                        Text("Dutch").tag("nl")
                    }
                    Divider()
                    Group {
                        Text("Chinese").tag("zh")
                        Text("Japanese").tag("ja")
                        Text("Korean").tag("ko")
                        Text("Hindi").tag("hi")
                        Text("Arabic").tag("ar")
                        Text("Russian").tag("ru")
                        Text("Turkish").tag("tr")
                        Text("Polish").tag("pl")
                        Text("Swedish").tag("sv")
                        Text("Ukrainian").tag("uk")
                    }
                }

                Text("Auto-detect works well for most cases. Set a specific language for better accuracy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Behavior
            Section("Behavior") {
                Toggle("Preserve clipboard after text injection", isOn: $appState.preserveClipboard)

            Toggle("Show mic indicator near cursor while recording", isOn: $appState.showCursorIndicator)

                Text("When enabled, your clipboard contents are restored after injecting text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Permissions
            Section("Permissions") {
                PermissionRow(
                    name: "Microphone",
                    icon: "mic.fill",
                    status: appState.micPermission,
                    action: { appState.requestMicrophonePermission() },
                    actionLabel: "Grant"
                )

                PermissionRow(
                    name: "Accessibility",
                    icon: "accessibility",
                    status: appState.accessibilityPermission,
                    action: { appState.requestAccessibilityPermission() },
                    actionLabel: "Open Settings"
                )

                PermissionRow(
                    name: "Input Monitoring",
                    icon: "keyboard",
                    status: appState.inputMonitoringPermission,
                    action: {
                        appState.requestInputMonitoringPermission()
                    },
                    actionLabel: "Open Settings"
                )

                Button("Re-check Permissions") {
                    appState.checkPermissions()
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let name: String
    let icon: String
    let status: PermissionStatus
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(name)
            Spacer()
            if status == .granted {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(actionLabel) { action() }
                    .controlSize(.small)
            }
        }
    }

    private var statusIcon: String {
        status == .granted ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        status == .granted ? .green : .red
    }
}

// MARK: - Model Settings

struct ModelSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var processMonitor = ProcessMonitor()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // System info
                if let capabilities = appState.systemCapabilities {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("System Information", systemImage: "cpu")
                                .font(.headline)
                                .padding(.bottom, 4)

                            HStack(spacing: 24) {
                                SystemInfoPill(icon: "cpu", label: "CPU", value: capabilities.processorName)
                                SystemInfoPill(icon: "memorychip", label: "RAM", value: "\(capabilities.physicalMemoryGB) GB")
                                SystemInfoPill(icon: "bolt.fill", label: "Metal", value: capabilities.supportsMetalAcceleration ? "Yes" : "No")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let recommended = appState.deviceRecommendedModel {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.blue)
                                    Text("WhisperKit recommends: **\(recommended)**")
                                        .font(.callout)
                                }
                                .padding(.top, 4)
                            }

                            // Disk usage
                            HStack {
                                Image(systemName: "internaldrive")
                                    .foregroundStyle(.secondary)
                                Text("Model storage: \(appState.modelManager.diskUsageDescription())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }
                        .padding(4)
                    }
                }

                // Resource usage
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Resource Usage", systemImage: "gauge.with.dots.needle.bottom.50percent")
                            .font(.headline)
                            .padding(.bottom, 4)

                        HStack(spacing: 24) {
                            SystemInfoPill(
                                icon: "cpu",
                                label: "CPU",
                                value: String(format: "%.1f%%", processMonitor.cpuUsage)
                            )
                            SystemInfoPill(
                                icon: "memorychip",
                                label: "Memory",
                                value: processMonitor.memoryMB >= 1024
                                    ? String(format: "%.1f GB", processMonitor.memoryMB / 1024)
                                    : String(format: "%.0f MB", processMonitor.memoryMB)
                            )
                            SystemInfoPill(
                                icon: "chart.line.uptrend.xyaxis",
                                label: "Peak",
                                value: processMonitor.memoryPeakMB >= 1024
                                    ? String(format: "%.1f GB", processMonitor.memoryPeakMB / 1024)
                                    : String(format: "%.0f MB", processMonitor.memoryPeakMB)
                            )
                            SystemInfoPill(
                                icon: "arrow.triangle.branch",
                                label: "Threads",
                                value: "\(processMonitor.threadCount)"
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(4)
                }

                // Currently active model
                if let current = appState.currentModel {
                    GroupBox {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text("Active Model: \(current.size.displayName)")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                Text("\(current.size.qualityDescription) quality • \(current.size.fileSizeDescription)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(4)
                    }
                }

                // Model list
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Available Models", systemImage: "list.bullet")
                            .font(.headline)
                            .padding(.bottom, 8)
                            .padding(.horizontal, 4)

                        ForEach(appState.availableModels) { model in
                            ModelRow(model: model, appState: appState)

                            if model.size != ModelSize.allCases.last {
                                Divider()
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                    .padding(4)
                }

                // Info text
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Models are downloaded from HuggingFace and cached locally. Larger models produce better results but are slower and use more memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

struct SystemInfoPill: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ModelRow: View {
    let model: WhisperModelInfo
    @ObservedObject var appState: AppState

    var body: some View {
        HStack {
            // Status icon
            Image(systemName: model.statusIconName)
                .foregroundStyle(model.isActive ? .green : .secondary)
                .frame(width: 20)

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.size.displayName)
                        .font(.callout)
                        .fontWeight(model.isActive ? .semibold : .regular)

                    if let recommended = appState.deviceRecommendedModel,
                       recommended.contains(model.size.rawValue) {
                        Text("Recommended")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }

                    if !model.isSupported {
                        Text("Unsupported")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 4) {
                    Text(model.size.fileSizeDescription)
                    Text("•")
                    Text(model.size.qualityDescription)
                    Text("•")
                    Text("~\(String(format: "%.0f", model.size.ramRequiredGB)) GB RAM")
                    Text("•")
                    Text("Speed: \(String(repeating: "⚡", count: max(1, 6 - model.size.relativeSpeed)))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Download progress or loading indicator
            if let progress = model.downloadProgress {
                VStack(spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 60)
                        .controlSize(.small)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if model.isLoading {
                VStack(spacing: 2) {
                    ProgressView()
                        .frame(width: 60)
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Action button
            if model.isActive {
                Label("Active", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if !model.isSupported {
                Text("Too Large")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.isLoading || model.downloadProgress != nil {
                // Show nothing - progress indicator handles the feedback
                EmptyView()
            } else if model.isDownloaded {
                Button("Load") {
                    Task { await appState.loadModel(model.size) }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Download & Load") {
                    Task {
                        await appState.downloadModel(model.size)
                        if appState.availableModels.first(where: { $0.size == model.size })?.isDownloaded == true {
                            await appState.loadModel(model.size)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// MARK: - Audio Settings

struct AudioSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var audioDevices: [AudioDevice] = []

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Max recording duration", selection: $appState.maxRecordingDuration) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("120 seconds").tag(120)
                    Text("300 seconds (5 min)").tag(300)
                }

                Text("Recording will automatically stop after this duration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Silence Detection") {
                HStack {
                    Text("Sensitivity")
                    Slider(
                        value: $appState.silenceThreshold,
                        in: 0.001...0.05,
                        step: 0.001
                    )
                    Text(sensitivityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                HStack {
                    Text("Auto-stop after silence")
                    Slider(
                        value: $appState.silenceDuration,
                        in: 0.5...5.0,
                        step: 0.5
                    )
                    Text("\(String(format: "%.1f", appState.silenceDuration))s")
                        .monospacedDigit()
                        .frame(width: 35)
                }

                Text("In double-tap mode, recording auto-stops after this duration of silence. In push-to-talk mode, you control when to stop by releasing the key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound Effects") {
                Toggle("Enable sound effects", isOn: $appState.soundEffectsEnabled)

                Text("Play subtle audio cues when recording starts and stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Input Device") {
                if audioDevices.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("No audio input devices found")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(audioDevices) { device in
                        HStack {
                            Image(systemName: device.isDefault ? "mic.circle.fill" : "mic.circle")
                                .foregroundStyle(device.isDefault ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.callout)
                                if device.isDefault {
                                    Text("System Default")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            if device.isDefault {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Button("Refresh Devices") {
                    audioDevices = AudioEngine.availableInputDevices()
                }
                .controlSize(.small)

                Text("VocaMac uses your system default input device. Change it in System Settings → Sound → Input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
        .onAppear {
            audioDevices = AudioEngine.availableInputDevices()
        }
    }

    private var sensitivityLabel: String {
        if appState.silenceThreshold < 0.01 { return "High" }
        if appState.silenceThreshold < 0.03 { return "Medium" }
        return "Low"
    }
}

// MARK: - About Tab

struct AboutTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App icon
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            // App name and version
            Text("VocaMac")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your voice, your Mac, your privacy.\nOpen-source dictation powered by AI.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Version 0.1.0 (Alpha)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            // Tech info
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    if let capabilities = appState.systemCapabilities {
                        InfoRow2(label: "Device", value: capabilities.processorName)
                        InfoRow2(label: "Architecture", value: capabilities.isAppleSilicon ? "Apple Silicon (ARM64)" : "Intel (x86_64)")
                        InfoRow2(label: "Neural Engine", value: capabilities.supportsMetalAcceleration ? "Available" : "Not Available")
                    }
                    InfoRow2(label: "Engine", value: "WhisperKit")
                    InfoRow2(label: "Model", value: appState.whisperService.loadedModelName ?? "Not loaded")
                    InfoRow2(label: "Storage", value: appState.modelManager.diskUsageDescription())
                }
                .font(.caption)
                .padding(4)
            }
            .frame(width: 300)

            Divider()
                .frame(width: 200)

            // Links
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://vocamac.com")!) {
                    Label("Website", systemImage: "globe")
                }
                Link(destination: URL(string: "https://github.com/jatinkrmalik/vocamac")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!) {
                    Label("WhisperKit", systemImage: "waveform")
                }
            }
            .font(.caption)

            Spacer()

            HStack(spacing: 0) {
                Text("Made with ❤️ by ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Link("Jatin Kumar Malik", destination: URL(string: "https://x.com/intent/user?screen_name=jatinkrmalik")!)
                    .font(.caption2)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct InfoRow2: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }
}

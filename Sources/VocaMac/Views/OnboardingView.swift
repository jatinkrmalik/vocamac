// OnboardingView.swift
// VocaMac
//
// Multi-step onboarding wizard for first-time users.
// Guides users through welcome, permissions, model selection, hotkey setup, and testing.

import SwiftUI

// MARK: - Onboarding Step Enum

/// Represents the current step in the onboarding flow
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case permissions = 1
    case modelSelection = 2
    case hotkeyConfig = 3
    case quickTest = 4
    case complete = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome to VocaMac"
        case .permissions: return "Grant Permissions"
        case .modelSelection: return "Choose Your Model"
        case .hotkeyConfig: return "Configure Hotkey"
        case .quickTest: return "Quick Test"
        case .complete: return "All Set!"
        }
    }

    var stepNumber: String {
        "Step \(rawValue + 1) of 6"
    }
}

// MARK: - OnboardingView

/// Main onboarding wizard container
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Step indicator
                HStack {
                    Text(currentStep.stepNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(OnboardingStep.allCases, id: \.self) { step in
                            Circle()
                                .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding()
                .borderBottom()

                // Step content
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeStep()
                    case .permissions:
                        PermissionsStep()
                    case .modelSelection:
                        ModelSelectionStep()
                    case .hotkeyConfig:
                        HotkeyConfigStep()
                    case .quickTest:
                        QuickTestStep()
                    case .complete:
                        CompleteStep()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Navigation buttons
                HStack(spacing: 12) {
                    if currentStep != .welcome {
                        Button(action: goToPreviousStep) {
                            Text("Back")
                        }
                        .keyboardShortcut(.cancelAction)
                    }

                    Spacer()

                    if currentStep != .complete {
                        Button(action: goToNextStep) {
                            Text(currentStep == .quickTest ? "Finish" : "Continue")
                        }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button(action: completeOnboarding) {
                            Text("Start Using VocaMac")
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 550)
        .onAppear {
            Task {
                await appState.performStartup()
            }
        }
    }

    // MARK: - Navigation

    private func goToNextStep() {
        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = nextStep
            }
        }
    }

    private func goToPreviousStep() {
        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = prevStep
            }
        }
    }

    private func completeOnboarding() {
        appState.completeOnboarding()
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            // App name and tagline
            VStack(spacing: 8) {
                Text("VocaMac")
                    .font(.system(size: 40, weight: .bold))

                Text("Your voice, your Mac, your privacy")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Description
            VStack(alignment: .leading, spacing: 12) {
                Label("Dictate directly into any app", systemImage: "doc.text")
                Label("All processing happens on your Mac", systemImage: "lock.fill")
                Label("No internet required, no data leaves your device", systemImage: "network.slash")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Spacer()

            Text("This guide will set up VocaMac in just a few minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 2: Permissions

struct PermissionsStep: View {
    @EnvironmentObject var appState: AppState

    private var allPermissionsGranted: Bool {
        appState.micPermission == .granted &&
        appState.accessibilityPermission == .granted &&
        appState.inputMonitoringPermission == .granted
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("VocaMac needs a few permissions to work properly.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            VStack(spacing: 12) {
                OnboardingPermissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    description: "Record audio for transcription",
                    status: appState.micPermission,
                    action: { appState.requestMicrophonePermission() }
                )

                OnboardingPermissionRow(
                    icon: "hand.raised.fill",
                    name: "Accessibility",
                    description: "Monitor hotkey presses to activate recording",
                    status: appState.accessibilityPermission,
                    action: { appState.requestAccessibilityPermission() }
                )

                OnboardingPermissionRow(
                    icon: "keyboard.fill",
                    name: "Input Monitoring",
                    description: "Detect keyboard and mouse input for activation",
                    status: appState.inputMonitoringPermission,
                    action: { appState.requestInputMonitoringPermission() }
                )
            }
            .padding()

            Spacer()

            if !allPermissionsGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("Some permissions are missing. VocaMac may not work correctly until all permissions are granted. You can set them later in Settings → Debug.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.yellow.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("You can grant these permissions in System Settings > Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Onboarding Permission Row

struct OnboardingPermissionRow: View {
    let icon: String
    let name: String
    let description: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 32)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if status == .granted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                } else {
                    Button(action: action) {
                        Text(status == .notDetermined ? "Grant" : "Open Settings")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .gray
        }
    }
}

// MARK: - Step 3: Model Selection

struct ModelSelectionStep: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose a model based on your device and needs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if let recommended = appState.deviceRecommendedModel,
               let recommendedSize = ModelSize.allCases.first(where: { recommended.contains($0.rawValue) }) {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("We recommend: **\(recommendedSize.displayName)**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(appState.availableModels) { modelInfo in
                        ModelSelectionCard(
                            modelInfo: modelInfo,
                            isRecommended: appState.deviceRecommendedModel?.contains(modelInfo.size.rawValue) == true,
                            onSelect: {
                                Task {
                                    await appState.loadModel(modelInfo.size)
                                }
                            },
                            onDownload: {
                                Task {
                                    await appState.downloadModel(modelInfo.size)
                                }
                            }
                        )
                    }
                }
                .padding()
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Model Selection Card

struct ModelSelectionCard: View {
    let modelInfo: WhisperModelInfo
    let isRecommended: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(modelInfo.size.displayName)
                            .font(.body)
                            .fontWeight(.semibold)
                        if isRecommended {
                            Label("Recommended", systemImage: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                        Spacer()
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Size")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(modelInfo.size.fileSizeDescription)
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(modelInfo.size.relativeSpeed)x")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quality")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(modelInfo.size.qualityDescription)
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Spacer()
                    }
                }

                Spacer()
            }

            HStack(spacing: 12) {
                if let progress = modelInfo.downloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if modelInfo.isDownloaded {
                    if modelInfo.isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button(action: onSelect) {
                            Text("Use This Model")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                } else if !modelInfo.isSupported {
                    Text("Not supported on this device")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Button(action: onDownload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("Download")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecommended ? Color.orange : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Step 4: Hotkey Configuration

struct HotkeyConfigStep: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose how to activate VocaMac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            VStack(spacing: 16) {
                // Activation Mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activation Mode")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Picker("Mode", selection: $appState.activationMode) {
                        ForEach(ActivationMode.allCases) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(appState.activationMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Hotkey Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hotkey")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Picker("Key", selection: $appState.hotKeyCode) {
                        ForEach(KeyCodeReference.commonHotKeys, id: \.keyCode) { hotKey in
                            Text(hotKey.name).tag(hotKey.keyCode)
                        }
                    }

                    Text("Press this key to start recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if appState.activationMode == .doubleTapToggle {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Double-tap Speed")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack {
                            Slider(
                                value: $appState.doubleTapThreshold,
                                in: 0.2...0.8,
                                step: 0.05
                            )
                            Text("\(String(format: "%.2f", appState.doubleTapThreshold))s")
                                .monospacedDigit()
                                .frame(width: 40)
                        }

                        Text("How fast you need to double-tap.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 5: Quick Test

struct QuickTestStep: View {
    @EnvironmentObject var appState: AppState
    @State private var isRecording = false
    @State private var testResult: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Let's test your setup with a quick recording.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 16) {
                // Recording button
                Button(action: toggleRecording) {
                    VStack(spacing: 8) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(isRecording ? .red : .blue)

                        Text(isRecording ? "Recording..." : "Click to Record")
                            .font(.body)
                            .fontWeight(.semibold)

                        if isRecording {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8)
                                    .scaleEffect(1.2)

                                Text("Recording audio...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .disabled(appState.appStatus == .processing)

                // Test result display
                if let result = testResult {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Transcription Result")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        Text(result)
                            .font(.subheadline)
                            .lineLimit(4)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                    }
                } else if appState.appStatus == .processing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("Try saying a short phrase like 'Hello world'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding()
    }

    private func toggleRecording() {
        if isRecording {
            Task {
                await appState.stopRecordingAndTranscribe()
                isRecording = false
            }
        } else {
            Task {
                await appState.startRecording()
                isRecording = true
            }
        }
    }
}

// MARK: - Step 6: Complete

struct CompleteStep: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            // Heading
            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("VocaMac is ready to use")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Summary
            VStack(alignment: .leading, spacing: 12) {
                SummaryItem(icon: "mic.fill", text: "Microphone access enabled")
                if appState.accessibilityPermission == .granted {
                    SummaryItem(icon: "hand.raised.fill", text: "Accessibility permission granted")
                }
                if appState.inputMonitoringPermission == .granted {
                    SummaryItem(icon: "keyboard.fill", text: "Input monitoring enabled")
                }
                SummaryItem(icon: "brain", text: "Model: \(appState.currentModel?.size.displayName ?? "Selected")")
                SummaryItem(icon: "keyboard", text: "Hotkey: \(KeyCodeReference.displayName(for: appState.hotKeyCode))")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(8)

            Spacer()

            Text("You can adjust settings anytime from the VocaMac menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }
}

struct SummaryItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.green)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }
}

// MARK: - Helpers

extension View {
    func borderBottom() -> some View {
        VStack(spacing: 0) {
            self
            Divider()
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}

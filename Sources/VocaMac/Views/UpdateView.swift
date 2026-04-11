// UpdateView.swift
// VocaMac
//
// Update banner and detail sheet for GitHub release updates.

import SwiftUI

struct UpdateBannerView: View {
    let info: UpdateInfo
    @EnvironmentObject var appState: AppState
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("Update \(info.tagName) available")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetails) {
            UpdateDetailView(info: info)
                .environmentObject(appState)
        }
    }
}

struct UpdateDetailView: View {
    let info: UpdateInfo
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VocaMac \(info.tagName) Available")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(info.dmgSize), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Later") {
                    appState.updateChecker.dismiss()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                Text(info.releaseNotes.isEmpty ? "No release notes provided." : info.releaseNotes)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxHeight: 280)

            Divider()

            actionArea
                .padding(20)
        }
        .frame(width: 480)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch appState.updateChecker.updateState {
        case .updateAvailable:
            HStack {
                Button("Skip This Version") {
                    appState.updateChecker.skipVersion(info.version)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Download & Install") {
                    Task {
                        await appState.updateChecker.downloadUpdate(info)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading update...")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        case .readyToInstall(let dmgPath):
            VStack(alignment: .leading, spacing: 10) {
                Label("Download complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Open the DMG and drag VocaMac to Applications to replace the existing app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open DMG") {
                    appState.updateChecker.openDMG(at: dmgPath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                HStack {
                    Button("View Release") {
                        NSWorkspace.shared.open(info.releasePageURL)
                    }
                    .buttonStyle(.bordered)

                    Button("Retry") {
                        Task {
                            await appState.updateChecker.downloadUpdate(info)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        default:
            EmptyView()
        }
    }
}

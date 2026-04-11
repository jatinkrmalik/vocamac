// UpdateView.swift
// VocaMac
//
// Update banner and detail sheet for GitHub release updates.

import SwiftUI
import AppKit

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
                Button("Later (24h)") {
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

            MarkdownReleaseNotesView(markdown: info.releaseNotes.isEmpty ? "No release notes provided." : info.releaseNotes)
                .frame(height: 280)
                .padding(20)

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
        case .downloading(let progress, let bytesDownloaded, let totalBytes, let eta):
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
                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if eta > 0 && eta < 3600 {
                        Text(formatETA(eta))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        case .verifying:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Verifying download integrity...")
                        .foregroundStyle(.secondary)
                }
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

    private func formatETA(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s remaining"
        }
        return "\(secs)s remaining"
    }
}

private struct MarkdownReleaseNotesView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: 10_000_000)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(renderedMarkdown())
    }

    /// Converts GitHub-flavored Markdown to HTML, then renders via NSAttributedString.
    private func renderedMarkdown() -> NSAttributedString {
        let htmlBody = markdownToHTML(markdown)
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? "#e0e0e0" : "#1d1d1f"
        let mutedColor = isDark ? "#999" : "#666"

        let fullHTML = """
        <html><head><style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 12px;
            color: \(textColor);
            line-height: 1.5;
            margin: 0;
            padding: 0;
        }
        h1, h2, h3, h4 {
            font-weight: 600;
            margin: 12px 0 6px 0;
        }
        h2 { font-size: 15px; }
        h3 { font-size: 13px; }
        ul, ol { padding-left: 20px; margin: 4px 0; }
        li { margin: 2px 0; }
        code {
            font-family: Menlo, monospace;
            font-size: 11px;
            background: \(isDark ? "#333" : "#f0f0f0");
            padding: 1px 4px;
            border-radius: 3px;
        }
        p { margin: 6px 0; }
        a { color: #007AFF; }
        strong { font-weight: 600; }
        em { font-style: italic; }
        hr { border: none; border-top: 1px solid \(mutedColor); margin: 10px 0; }
        </style></head><body>\(htmlBody)</body></html>
        """

        guard let data = fullHTML.data(using: String.Encoding.utf8),
              let attributed = NSAttributedString(
                html: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return NSAttributedString(string: markdown)
        }

        return attributed
    }

    /// Basic Markdown to HTML converter for GitHub release notes.
    private func markdownToHTML(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var html = ""
        var inList = false

        for i in 0..<lines.count {
            let line = lines[i]

            // Close list if we leave a list context
            if inList && !line.hasPrefix("- ") && !line.hasPrefix("* ") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                html += "</ul>\n"
                inList = false
            }

            // Headings
            if line.hasPrefix("#### ") {
                html += "<h4>\(inlineMarkdown(String(line.dropFirst(5))))</h4>\n"
                continue
            }
            if line.hasPrefix("### ") {
                html += "<h3>\(inlineMarkdown(String(line.dropFirst(4))))</h3>\n"
                continue
            }
            if line.hasPrefix("## ") {
                html += "<h2>\(inlineMarkdown(String(line.dropFirst(3))))</h2>\n"
                continue
            }
            if line.hasPrefix("# ") {
                html += "<h1>\(inlineMarkdown(String(line.dropFirst(2))))</h1>\n"
                continue
            }

            // Horizontal rule
            if line.trimmingCharacters(in: .whitespaces) == "---" ||
               line.trimmingCharacters(in: .whitespaces) == "***" {
                html += "<hr>\n"
                continue
            }

            // Unordered list items
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList {
                    html += "<ul>\n"
                    inList = true
                }
                let content = String(line.dropFirst(2))
                html += "<li>\(inlineMarkdown(content))</li>\n"
                continue
            }

            // Empty lines = paragraph break
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                html += "<br>\n"
                continue
            }

            // Regular paragraph
            html += "<p>\(inlineMarkdown(line))</p>\n"
        }

        if inList {
            html += "</ul>\n"
        }

        return html
    }

    /// Handles inline markdown: bold, italic, code, links.
    private func inlineMarkdown(_ text: String) -> String {
        var result = text

        // Escape HTML entities (but preserve existing tags we might add)
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")

        // Inline code: `code`
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )

        // Bold: **text** or __text__
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "__(.+?)__",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )

        // Italic: *text* or _text_
        result = result.replacingOccurrences(
            of: "(?<!\\w)\\*(.+?)\\*(?!\\w)",
            with: "<em>$1</em>",
            options: .regularExpression
        )

        // Links: [text](url)
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        // GitHub issue/PR references: #123
        result = result.replacingOccurrences(
            of: "#(\\d+)",
            with: "<a href=\"https://github.com/jatinkrmalik/vocamac/issues/$1\">#$1</a>",
            options: .regularExpression
        )

        return result
    }
}

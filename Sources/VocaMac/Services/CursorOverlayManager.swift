// CursorOverlayManager.swift
// VocaMac
//
// Shows a floating mic indicator near the text cursor during recording.
// Uses the Accessibility API to locate the caret position in the focused app,
// then renders a small, non-interactive overlay that shows recording/processing state.

import AppKit
import SwiftUI

// MARK: - CursorOverlayManager

@MainActor
final class CursorOverlayManager {

    // MARK: - Properties

    /// The floating panel that hosts the mic indicator
    private var overlayPanel: NSPanel?

    /// Hosting view for the SwiftUI indicator content
    private var hostingView: NSHostingView<MicIndicatorView>?

    /// The SwiftUI view model driving the indicator
    private let viewModel = MicIndicatorViewModel()

    /// Timer to periodically reposition the overlay to follow the cursor
    private var repositionTimer: Timer?

    // MARK: - Public API

    /// Show the recording indicator near the text cursor
    func show() {
        guard overlayPanel == nil else {
            // Already showing - just ensure it's in recording state
            viewModel.phase = .recording
            return
        }

        viewModel.phase = .recording

        let indicatorView = MicIndicatorView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: indicatorView)
        hosting.frame = NSRect(x: 0, y: 0, width: 36, height: 36)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 36, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = hosting

        // Position near the text cursor
        positionNearCaret(panel)

        panel.orderFront(nil)
        overlayPanel = panel
        hostingView = hosting

        // Reposition periodically in case the user scrolls or the cursor moves
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let panel = self.overlayPanel else { return }
                self.positionNearCaret(panel)
            }
        }

        viewModel.isActive = true
        VocaLogger.debug(.cursorOverlay, "Indicator shown (recording)")
    }

    /// Transition the indicator from recording (red) to processing (purple)
    /// Keeps the overlay visible so the user knows text is on its way.
    func transitionToProcessing() {
        viewModel.phase = .processing
        VocaLogger.debug(.cursorOverlay, "Transitioned to processing")
    }

    /// Hide the recording indicator
    func hide() {
        repositionTimer?.invalidate()
        repositionTimer = nil
        viewModel.isActive = false
        viewModel.phase = .idle
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
        hostingView = nil
        VocaLogger.debug(.cursorOverlay, "Indicator hidden")
    }

    /// Update the audio level (kept for future use)
    func updateAudioLevel(_ level: Float) {
        viewModel.audioLevel = level
    }

    // MARK: - Caret Position Detection

    /// Position the panel near the text caret using the Accessibility API.
    /// Falls back to positioning near the mouse cursor if the caret can't be found.
    private func positionNearCaret(_ panel: NSPanel) {
        if let caretRect = getCaretRect() {
            // Place the indicator just above and to the right of the caret
            let screenPoint = NSPoint(
                x: caretRect.origin.x + caretRect.width + 4,
                y: caretRect.origin.y + caretRect.height + 4
            )
            panel.setFrameOrigin(screenPoint)
        } else {
            // Fallback: position near the mouse cursor
            let mouseLocation = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(
                x: mouseLocation.x + 16,
                y: mouseLocation.y - 40
            ))
        }
    }

    /// Use the Accessibility API to get the bounding rect of the text caret
    /// in the currently focused application.
    ///
    /// The Accessibility API returns coordinates in the macOS global coordinate
    /// system (top-left origin, with (0,0) at the top-left of the primary screen).
    /// NSWindow/NSPanel uses the AppKit coordinate system (bottom-left origin).
    /// We must convert between these systems using the *primary screen's height*
    /// — not NSScreen.main — to handle multi-monitor setups properly.
    private func getCaretRect() -> CGRect? {
        // Get the focused application
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else {
            return nil
        }

        // Get the focused UI element (usually a text field)
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }

        let element = focusedElement as! AXUIElement

        // Get the selected text range (caret position)
        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            return nil
        }

        // Get the bounds of the selected range (caret position on screen)
        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &bounds
        ) == .success else {
            return nil
        }

        // Convert AXValue to CGRect
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // Convert from AX (top-left origin) to AppKit (bottom-left origin).
        //
        // The AX global coordinate system places (0,0) at the top-left corner
        // of the primary display, with Y increasing downward. AppKit places
        // (0,0) at the bottom-left of the primary display with Y going up.
        //
        // To convert correctly on multi-monitor setups we must use the
        // *primary* screen's height (NSScreen.screens.first) — not
        // NSScreen.main (the screen with the current key window). The AX
        // coordinate space is always anchored to the primary display, so
        // using any other screen's dimensions produces wrong results when
        // the caret is on a secondary monitor.
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        rect.origin.y = primaryScreenHeight - rect.origin.y - rect.height

        return rect
    }
}

// MARK: - CursorOverlayManaging Conformance

extension CursorOverlayManager: CursorOverlayManaging {}

// MARK: - IndicatorPhase

enum IndicatorPhase {
    case idle
    case recording
    case processing
}

// MARK: - MicIndicatorViewModel

@MainActor
final class MicIndicatorViewModel: ObservableObject {
    @Published var isActive: Bool = false
    @Published var audioLevel: Float = 0.0
    @Published var phase: IndicatorPhase = .idle
}

// MARK: - MicIndicatorView

struct MicIndicatorView: View {
    @ObservedObject var viewModel: MicIndicatorViewModel

    /// Recording state - red, matching menu bar icon (.systemRed)
    private let recordingColor = Color(nsColor: .systemRed)

    /// Processing state - purple (#BF5AF2), matching menu bar icon
    private let processingColor = Color(
        red: 0.749, green: 0.353, blue: 0.949
    )

    var body: some View {
        ZStack {
            // Background circle with color transition
            Circle()
                .fill(phaseColor)
                .frame(width: 28, height: 28)
                .shadow(color: phaseColor.opacity(0.4), radius: 4, x: 0, y: 0)

            // Icon changes based on phase
            Image(systemName: phaseIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .opacity(viewModel.isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isActive)
        .animation(.easeInOut(duration: 0.4), value: viewModel.phase)
    }

    /// Color based on current phase
    private var phaseColor: Color {
        switch viewModel.phase {
        case .idle:       return recordingColor
        case .recording:  return recordingColor
        case .processing: return processingColor
        }
    }

    /// Icon based on current phase
    private var phaseIcon: String {
        switch viewModel.phase {
        case .idle:       return "mic.fill"
        case .recording:  return "mic.fill"
        case .processing: return "ellipsis.circle"
        }
    }
}

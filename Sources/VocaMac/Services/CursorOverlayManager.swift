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

    private func positionNearCaret(_ panel: NSPanel) {
        panel.setFrameOrigin(detectIndicatorPosition())
    }

    private func detectIndicatorPosition() -> NSPoint {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success else {
            return mousePosition()
        }
        let app = focusedApp as! AXUIElement

        var focusedElement: AnyObject?
        if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
           focusedElement != nil {
            let element = focusedElement as! AXUIElement

            if let caretRect = getCaretRectFromElement(element) {
                VocaLogger.debug(.cursorOverlay, "Positioned via caret")
                return clamped(NSPoint(x: caretRect.maxX + 4, y: caretRect.maxY + 4))
            }

            if let elementRect = convertAXRectToAppKit(getElementRect(element)) {
                VocaLogger.debug(.cursorOverlay, "Positioned via focused element")
                return clamped(NSPoint(x: elementRect.maxX + 4, y: elementRect.maxY - 4))
            }
        }

        if let windowRect = convertAXRectToAppKit(getFocusedWindowRect(app)) {
            VocaLogger.debug(.cursorOverlay, "Positioned via focused window")
            return clamped(NSPoint(x: windowRect.maxX - 60, y: windowRect.maxY - 50))
        }

        VocaLogger.debug(.cursorOverlay, "Positioned via mouse cursor (fallback)")
        return mousePosition()
    }

    private func getCaretRectFromElement(_ element: AXUIElement) -> CGRect? {
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        guard rangeResult == .success, let range = selectedRange else { return nil }

        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }

        return convertAXRectToAppKit(rect)
    }

    private func getElementRect(_ element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success else { return nil }

        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGRect(origin: position, size: size)
    }

    private func getFocusedWindowRect(_ app: AXUIElement) -> CGRect? {
        var window: AnyObject?
        var result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window)

        if result != .success {
            result = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &window)
        }

        guard result == .success, window != nil else { return nil }
        return getElementRect(window as! AXUIElement)
    }

    // MARK: - Coordinate Helpers

    private func convertAXRectToAppKit(_ rect: CGRect?) -> CGRect? {
        guard let rect, let primaryScreenHeight = NSScreen.screens.first?.frame.height else { return nil }
        var converted = rect
        converted.origin.y = primaryScreenHeight - rect.origin.y - rect.height
        return converted
    }

    private func mousePosition() -> NSPoint {
        let loc = NSEvent.mouseLocation
        return NSPoint(x: loc.x + 16, y: loc.y - 40)
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        let panelSize = CGSize(width: 36, height: 36)
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                let visible = screen.visibleFrame
                return NSPoint(
                    x: min(max(point.x, visible.minX), visible.maxX - panelSize.width),
                    y: min(max(point.y, visible.minY), visible.maxY - panelSize.height)
                )
            }
        }
        return point
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

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
    ///
    /// Uses a tiered fallback strategy:
    /// 1. Exact caret position via AX text attributes (works in native AppKit/SwiftUI apps)
    /// 2. Focused element position/size (works in apps with partial AX support)
    /// 3. Focused window position (works in almost all apps)
    /// 4. Mouse cursor on the focused app's screen (last resort)
    private func positionNearCaret(_ panel: NSPanel) {
        let result = detectIndicatorPosition()
        panel.setFrameOrigin(result.point)
    }

    /// The method used to determine the indicator position, for logging/debugging.
    enum PositionSource: String {
        case caret = "caret"
        case focusedElement = "focused_element"
        case focusedWindow = "focused_window"
        case mouseCursor = "mouse_cursor"
    }

    /// Result of indicator position detection.
    struct PositionResult {
        let point: NSPoint
        let source: PositionSource
    }

    /// Detect the best position for the indicator using tiered fallback.
    ///
    /// This is extracted as a separate method (returning a result struct) to
    /// make the fallback strategy testable and debuggable.
    func detectIndicatorPosition() -> PositionResult {
        let systemWide = AXUIElementCreateSystemWide()

        // Step 1: Get the focused application
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        ) == .success else {
            VocaLogger.debug(.cursorOverlay, "AX step 1 failed: no focused application")
            return mousePosition()
        }

        let app = focusedApp as! AXUIElement

        // Step 2: Get the focused UI element
        var focusedElement: AnyObject?
        let step2Result = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        if step2Result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement

            // Step 3: Try exact caret position (full AX text support)
            if let caretRect = getCaretRectFromElement(axElement) {
                return PositionResult(
                    point: NSPoint(
                        x: caretRect.origin.x + caretRect.width + 4,
                        y: caretRect.origin.y + caretRect.height + 4
                    ),
                    source: .caret
                )
            }

            // Step 4: Try focused element's position + size
            // (better than mouse cursor — at least near the text field)
            if let elementRect = getElementRect(axElement) {
                VocaLogger.debug(.cursorOverlay, "Using focused element position fallback")
                let appKitRect = convertAXRectToAppKit(elementRect)
                // Position at the top-right corner of the focused element
                return PositionResult(
                    point: NSPoint(
                        x: appKitRect.origin.x + appKitRect.width + 4,
                        y: appKitRect.origin.y + appKitRect.height - 4
                    ),
                    source: .focusedElement
                )
            }
        } else {
            VocaLogger.debug(.cursorOverlay, "AX step 2 failed: no focused element (code: \(step2Result.rawValue))")
        }

        // Step 5: Try the focused app's main/focused window position
        if let windowRect = getFocusedWindowRect(app) {
            VocaLogger.debug(.cursorOverlay, "Using focused window position fallback")
            let appKitRect = convertAXRectToAppKit(windowRect)
            // Position at the top-right area of the window's content area
            // Offset inward so it doesn't overlap window chrome
            return PositionResult(
                point: NSPoint(
                    x: appKitRect.origin.x + appKitRect.width - 60,
                    y: appKitRect.origin.y + appKitRect.height - 50
                ),
                source: .focusedWindow
            )
        }

        // Step 6: Last resort — mouse cursor
        VocaLogger.debug(.cursorOverlay, "All AX fallbacks failed, using mouse cursor position")
        return mousePosition()
    }

    /// Try to get the exact caret bounding rect from a focused text element.
    /// Requires the element to support kAXSelectedTextRangeAttribute and
    /// kAXBoundsForRangeParameterizedAttribute.
    private func getCaretRectFromElement(_ element: AXUIElement) -> CGRect? {
        // Get the selected text range (caret position)
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )
        guard rangeResult == .success else {
            VocaLogger.debug(.cursorOverlay, "AX step 3 failed: kAXSelectedTextRangeAttribute not supported (code: \(rangeResult.rawValue))")
            return nil
        }

        // Get the bounds of the selected range
        var bounds: AnyObject?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &bounds
        )
        guard boundsResult == .success else {
            VocaLogger.debug(.cursorOverlay, "AX step 4 failed: kAXBoundsForRangeParameterizedAttribute not supported (code: \(boundsResult.rawValue))")
            return nil
        }

        // Convert AXValue to CGRect
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            VocaLogger.debug(.cursorOverlay, "AX step 4 failed: could not extract CGRect from AXValue")
            return nil
        }

        return convertAXRectToAppKit(rect)
    }

    /// Get the position and size of an AXUIElement via kAXPositionAttribute
    /// and kAXSizeAttribute. Works for many elements that don't support
    /// the full text caret attributes (e.g., Electron text areas, terminal views).
    private func getElementRect(_ element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success else {
            VocaLogger.debug(.cursorOverlay, "Focused element fallback failed: kAXPositionAttribute not available")
            return nil
        }

        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success else {
            VocaLogger.debug(.cursorOverlay, "Focused element fallback failed: kAXSizeAttribute not available")
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    /// Get the focused (or main) window's position and size from the app element.
    private func getFocusedWindowRect(_ app: AXUIElement) -> CGRect? {
        // Try the focused window first
        var window: AnyObject?
        var result = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &window
        )

        // Fall back to the main window
        if result != .success {
            result = AXUIElementCopyAttributeValue(
                app,
                kAXMainWindowAttribute as CFString,
                &window
            )
        }

        guard result == .success, let windowElement = window else {
            VocaLogger.debug(.cursorOverlay, "Window fallback failed: no focused/main window (code: \(result.rawValue))")
            return nil
        }

        return getElementRect(windowElement as! AXUIElement)
    }

    // MARK: - Coordinate Conversion

    /// Convert a rect from AX coordinates (top-left origin) to AppKit coordinates
    /// (bottom-left origin).
    ///
    /// The AX global coordinate system places (0,0) at the top-left corner
    /// of the primary display, with Y increasing downward. AppKit places
    /// (0,0) at the bottom-left of the primary display with Y going up.
    ///
    /// To convert correctly on multi-monitor setups we must use the
    /// *primary* screen's height (NSScreen.screens.first) — not
    /// NSScreen.main (the screen with the current key window). The AX
    /// coordinate space is always anchored to the primary display, so
    /// using any other screen's dimensions produces wrong results when
    /// the caret is on a secondary monitor.
    private func convertAXRectToAppKit(_ rect: CGRect) -> CGRect {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        var converted = rect
        converted.origin.y = primaryScreenHeight - rect.origin.y - rect.height
        return converted
    }

    /// Mouse cursor fallback — positions the indicator near the mouse cursor.
    private func mousePosition() -> PositionResult {
        let mouseLocation = NSEvent.mouseLocation
        return PositionResult(
            point: NSPoint(
                x: mouseLocation.x + 16,
                y: mouseLocation.y - 40
            ),
            source: .mouseCursor
        )
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

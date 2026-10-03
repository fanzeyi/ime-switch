import AppKit
import ApplicationServices

/// Finds the on-screen text caret of the focused app via the Accessibility API.
enum CaretLocator {
    /// Caret rect in Cocoa screen coordinates (bottom-left origin), or nil if unavailable.
    @MainActor
    static func caretRect() -> NSRect? {
        guard let focused = focusedElement() else { return nil }
        AXUIElementSetMessagingTimeout(focused, 0.05)

        if let rangeValue = axValue(focused, kAXSelectedTextRangeAttribute) {
            var bounds: CFTypeRef?
            let err = AXUIElementCopyParameterizedAttributeValue(
                focused, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds)
            if err == .success, let bounds, let rect = plausibleCaret(bounds) {
                return rect
            }
        }

        // Web engines (Firefox, Safari, Chromium) expose the caret through text markers.
        if let caret = textMarkerCaret(focused) {
            return caret
        }

        // Fall back to the focused element's frame (e.g. terminals, some Electron apps).
        if let posValue = axValue(focused, kAXPositionAttribute),
           let sizeValue = axValue(focused, kAXSizeAttribute) {
            var origin = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(posValue, .cgPoint, &origin), AXValueGetValue(sizeValue, .cgSize, &size),
               size.width > 0, size.height > 0, size.height < 200 {
                return toCocoa(CGRect(origin: origin, size: size))
            }
        }
        return nil
    }

    @MainActor
    private static func textMarkerCaret(_ element: AXUIElement) -> NSRect? {
        guard let range = attribute(element, "AXSelectedTextMarkerRange") else { return nil }
        if let bounds = parameterized(element, "AXBoundsForTextMarkerRange", range),
           let rect = plausibleCaret(bounds) {
            return rect
        }
        // A collapsed range can report an empty rect; measure the next character instead
        // and keep only its leading edge.
        guard let start = parameterized(element, "AXStartTextMarkerForTextMarkerRange", range),
              let next = parameterized(element, "AXNextTextMarkerForTextMarker", start),
              let span = parameterized(element, "AXTextMarkerRangeForUnorderedTextMarkers", [start, next] as CFArray),
              let bounds = parameterized(element, "AXBoundsForTextMarkerRange", span),
              let rect = plausibleCaret(bounds)
        else { return nil }
        return NSRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
    }

    private static func parameterized(_ element: AXUIElement, _ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success
        else { return nil }
        return value
    }

    /// Converts an AX rect to Cocoa coordinates, rejecting the empty or off-screen rects
    /// apps return when there is no real caret.
    @MainActor
    private static func plausibleCaret(_ value: CFTypeRef) -> NSRect? {
        guard let rect = rect(from: value), rect.width >= 0, rect.height > 0, rect.height < 200 else { return nil }
        let cocoa = toCocoa(rect)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(cocoa.insetBy(dx: -1, dy: -1)) }) else { return nil }
        return cocoa
    }

    /// The system-wide element's focused attribute fails with kAXErrorCannotComplete on
    /// recent macOS, so ask the frontmost app directly and only fall back to system-wide.
    @MainActor
    private static func focusedElement() -> AXUIElement? {
        var roots: [AXUIElement] = []
        if let app = NSWorkspace.shared.frontmostApplication {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // Electron apps only expose their accessibility tree when asked.
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            roots.append(element)
        }
        roots.append(AXUIElementCreateSystemWide())

        for root in roots {
            AXUIElementSetMessagingTimeout(root, 0.05)
            if let value = attribute(root, kAXFocusedUIElementAttribute),
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func rect(from value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// AX uses a top-left origin anchored at the primary screen.
    @MainActor
    private static func toCocoa(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

import AppKit
import ApplicationServices

/// Opens Emoji & Symbols in the app the user is typing in, the way the system Input menu
/// does. A background app can't ask for that directly: `orderFrontCharacterPalette` and
/// selecting the palette input source both act on our own process and show nothing.
@MainActor
enum EmojiPicker {
    static func show() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        // Let our menu close and focus settle back on the app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !pressMenuItem(in: app.processIdentifier) {
                sendDefaultShortcut()
            }
        }
    }

    /// Presses the app's own Edit → Emoji & Symbols item, which works whatever shortcut
    /// the user assigned to it.
    private static func pressMenuItem(in pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let menuBar: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return false }
        for barItem in children(menuBar) {
            for menu in children(barItem) {
                for item in children(menu) {
                    if let title: String = attribute(item, kAXTitleAttribute), titles.contains(title) {
                        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                    }
                }
            }
        }
        return false
    }

    /// For apps whose menu we can't read: ⌃⌘Space, the item's default key equivalent.
    private static func sendDefaultShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(HotkeyTap.spaceKey), keyDown: keyDown)
            event?.flags = [.maskControl, .maskCommand]
            // Past our own tap, in case ⌃⌘Space is one of the per-source shortcuts.
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// The item's title in every language AppKit is localized in, since the frontmost app
    /// may run in a different language than we do.
    private static let titles: Set<String> = {
        let key = "Emoji & Symbols"
        var titles: Set<String> = [key]
        if let url = Bundle(for: NSApplication.self).url(forResource: "InputManager", withExtension: "loctable"),
           let table = NSDictionary(contentsOf: url) as? [String: [String: Any]] {
            for strings in table.values {
                if let title = strings[key] as? String { titles.insert(title) }
            }
        }
        return titles
    }()

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) ?? []
    }
}

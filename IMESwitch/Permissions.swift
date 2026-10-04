import AppKit
import ApplicationServices

enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openKeyboardShortcutSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    /// The Keyboard pane; Input Sources is a sheet behind its "Edit…" button, with no URL
    /// of its own.
    static func openInputSourceSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    /// Enabled system shortcuts on the switcher's keys, which would fight with it, by name.
    /// Its ⇧ variant only matters while cycling, when our event tap already has the keys;
    /// macOS also keeps an enabled ⌘⇧Space (ID 263) that System Settings doesn't show.
    static func conflictingSystemShortcuts() -> [String] {
        let switcher = ShortcutStore.savedSwitcher
        let names: [Int: String] = [
            60: String(localized: "Select the previous input source"),
            61: String(localized: "Select next source in Input menu"),
            64: String(localized: "Show Spotlight search"),
        ]
        // Pick up changes made in System Settings since the last read.
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        let hotkeys = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] ?? [:]
        var conflicts: [String] = []
        for (key, entry) in hotkeys.sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }) {
            guard let id = Int(key),
                  let entry = entry as? [String: Any],
                  entry["enabled"] as? Bool == true,
                  let value = entry["value"] as? [String: Any],
                  let params = value["parameters"] as? [Int], params.count == 3,
                  // [character, key code, modifiers as NSEvent/CGEvent flags]
                  Shortcut(keyCode: Int64(params[1]), flags: CGEventFlags(rawValue: UInt64(params[2]))) == switcher
            else { continue }
            conflicts.append(names[id] ?? String(localized: "Another system shortcut"))
        }
        // Shortcuts never changed from their default may be missing from the preferences.
        if conflicts.isEmpty, Shortcut.systemShortcuts().contains(switcher) {
            conflicts.append(String(localized: "Another system shortcut"))
        }
        return conflicts
    }
}

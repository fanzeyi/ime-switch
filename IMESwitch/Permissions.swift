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

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    /// System shortcuts that are still bound to cmd+space and would fight with us.
    static func conflictingSystemShortcuts() -> [String] {
        let names: [String: String] = [
            "60": String(localized: "Select the previous input source"),
            "61": String(localized: "Select next source in Input menu"),
            "64": String(localized: "Show Spotlight search"),
        ]
        // Pick up changes made in System Settings since the last read.
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        guard let hotkeys = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] else {
            return []
        }
        return names.keys.sorted().compactMap { key in
            guard let entry = hotkeys[key] as? [String: Any],
                  (entry["enabled"] as? Bool) == true,
                  let value = entry["value"] as? [String: Any],
                  let params = value["parameters"] as? [Int],
                  params.count == 3,
                  params[1] == 49,
                  params[2] == Int(CGEventFlags.maskCommand.rawValue)
            else { return nil }
            return names[key]
        }
    }
}

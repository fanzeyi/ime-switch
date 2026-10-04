import AppKit
import Carbon

/// A key plus modifiers: the switcher shortcut, or one that switches straight to an input
/// source.
struct Shortcut: Codable, Hashable, Sendable {
    let keyCode: Int64
    /// Raw `CGEventFlags`, limited to `Shortcut.modifierMask`.
    let modifiers: UInt64

    static let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    init(keyCode: Int64, flags: CGEventFlags) {
        self.keyCode = keyCode
        modifiers = flags.intersection(Self.modifierMask).rawValue
    }

    init(event: NSEvent) {
        // NSEvent and CGEvent modifier flags share their bit values.
        self.init(keyCode: Int64(event.keyCode), flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
    }

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    static let defaultSwitcher = Shortcut(keyCode: HotkeyTap.spaceKey, flags: .maskCommand)

    /// The same shortcut with ⇧ added, which cycles backwards when this is the switcher.
    var reversed: Shortcut { Shortcut(keyCode: keyCode, flags: flags.union(.maskShift)) }

    private var hasHoldableModifier: Bool {
        !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
    }

    enum Problem {
        case needsModifier
        case reserved
        case usedBySystem
    }

    /// For a per-source shortcut. Plain keys would fire while typing, so it needs ⌘, ⌃ or
    /// ⌥, unless it is a function key. The switcher is taken (its ⇧ variant isn't: that only
    /// goes backwards while cycling), and enabled macOS shortcuts (Mission Control,
    /// screenshots, …) would fight with ours.
    func problem(switcher: Shortcut) -> Problem? {
        if self == switcher {
            return .reserved
        }
        if !hasHoldableModifier, !Self.functionKeys.keys.contains(keyCode) {
            return .needsModifier
        }
        if Self.systemShortcuts().contains(self) {
            return .usedBySystem
        }
        return nil
    }

    enum SwitcherProblem {
        case needsHeldModifier
        case includesShift
        case escape
    }

    /// For the switcher, which works like ⌘Tab: it needs ⌘, ⌃ or ⌥ to hold down while
    /// cycling, ⇧ is left for going backwards and Esc for cancelling. A system shortcut on
    /// the same keys isn't a problem here; setup asks to turn it off.
    var switcherProblem: SwitcherProblem? {
        if keyCode == Self.escapeKey { return .escape }
        if flags.contains(.maskShift) { return .includesShift }
        if !hasHoldableModifier { return .needsHeldModifier }
        return nil
    }

    static let escapeKey: Int64 = 53

    /// The enabled shortcuts in System Settings → Keyboard → Keyboard Shortcuts.
    static func systemShortcuts() -> Set<Shortcut> {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let hotKeys = array?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        let carbonModifiers: [(Int, CGEventFlags)] = [
            (cmdKey, .maskCommand), (shiftKey, .maskShift), (optionKey, .maskAlternate), (controlKey, .maskControl),
        ]
        return Set(hotKeys.compactMap { hotKey in
            guard hotKey["kHISymbolicHotKeyEnabled"] as? Bool == true,
                  let code = hotKey["kHISymbolicHotKeyCode"] as? Int, code != 0xFFFF,
                  let modifiers = hotKey["kHISymbolicHotKeyModifiers"] as? Int else {
                return nil
            }
            var flags: CGEventFlags = []
            for (carbon, flag) in carbonModifiers where modifiers & carbon != 0 {
                flags.insert(flag)
            }
            return Shortcut(keyCode: Int64(code), flags: flags)
        })
    }

    /// As shown in menus, e.g. "⌃⌥1" or "⇧F5".
    var displayString: String {
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + keyName
    }

    var keyName: String {
        if let name = Self.functionKeys[keyCode] ?? Self.specialKeys[keyCode]?.name { return name }
        return Self.translate(keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// For `NSMenuItem.keyEquivalent`, which only displays the shortcut here: the event tap
    /// handles the key before any menu sees it.
    var menuKeyEquivalent: String? {
        if let index = Self.functionKeyOrder.firstIndex(of: keyCode) {
            return String(Character(UnicodeScalar(NSF1FunctionKey + index)!))
        }
        if let special = Self.specialKeys[keyCode] { return special.equivalent }
        return Self.translate(keyCode)?.lowercased()
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    }

    // MARK: - Key names

    private static let functionKeyOrder: [Int64] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    private static let functionKeys: [Int64: String] = Dictionary(
        uniqueKeysWithValues: functionKeyOrder.enumerated().map { ($1, "F\($0 + 1)") }
    )

    private static func scalar(_ value: Int) -> String {
        String(Character(UnicodeScalar(value)!))
    }

    private static let specialKeys: [Int64: (name: String, equivalent: String)] = [
        36: ("↩", "\r"),
        48: ("⇥", "\t"),
        49: ("Space", " "),
        51: ("⌫", "\u{8}"),
        53: ("⎋", "\u{1b}"),
        76: ("⌤", "\u{3}"),
        117: ("⌦", scalar(NSDeleteFunctionKey)),
        115: ("↖", scalar(NSHomeFunctionKey)),
        119: ("↘", scalar(NSEndFunctionKey)),
        116: ("⇞", scalar(NSPageUpFunctionKey)),
        121: ("⇟", scalar(NSPageDownFunctionKey)),
        123: ("←", scalar(NSLeftArrowFunctionKey)),
        124: ("→", scalar(NSRightArrowFunctionKey)),
        125: ("↓", scalar(NSDownArrowFunctionKey)),
        126: ("↑", scalar(NSUpArrowFunctionKey)),
    ]

    /// The character the key types in the current ASCII-capable layout, so names follow
    /// the user's keyboard (e.g. AZERTY) even while a CJK input method is selected.
    private static func translate(_ keyCode: Int64) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer in
            UCKeyTranslate(
                buffer.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        return text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty ? nil : text
    }
}

/// The switcher shortcut, per-input-source shortcuts keyed by input source ID, and the
/// sources the switcher skips. Settings for sources that are currently disabled are kept,
/// so re-enabling one brings them back.
@MainActor
final class ShortcutStore: ObservableObject {
    private static let defaultsKey = "InputSourceShortcuts"
    nonisolated private static let switcherDefaultsKey = "SwitcherShortcut"
    private static let excludedDefaultsKey = "ExcludedInputSources"

    @Published private(set) var shortcuts: [String: Shortcut]
    @Published private(set) var switcher: Shortcut
    /// Sources the switcher skips; they're still reachable by shortcut or from the menu.
    @Published private(set) var excluded: Set<String>

    /// The saved switcher, for code that doesn't hold the store.
    nonisolated static var savedSwitcher: Shortcut { switcher(in: .standard) }

    nonisolated private static func switcher(in defaults: UserDefaults) -> Shortcut {
        guard let data = defaults.data(forKey: switcherDefaultsKey),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
              shortcut.switcherProblem == nil
        else { return .defaultSwitcher }
        return shortcut
    }

    /// Called after any change.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    /// `defaults` other than `.standard` is for previews, which share the app's domain.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = [:]
        }
        switcher = Self.switcher(in: defaults)
        excluded = Set(defaults.stringArray(forKey: Self.excludedDefaultsKey) ?? [])
    }

    func setExcluded(_ isExcluded: Bool, for id: String) {
        guard excluded.contains(id) != isExcluded else { return }
        if isExcluded {
            excluded.insert(id)
        } else {
            excluded.remove(id)
        }
        defaults.set(excluded.sorted(), forKey: Self.excludedDefaultsKey)
        onChange?()
    }

    /// Changes the switcher, taking it away from any input source.
    func setSwitcher(_ shortcut: Shortcut) {
        switcher = shortcut
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: Self.switcherDefaultsKey)
        if shortcuts.values.contains(shortcut) {
            shortcuts = shortcuts.filter { $0.value != shortcut }
            saveShortcuts()
        }
        onChange?()
    }

    func sourceID(for shortcut: Shortcut) -> String? {
        shortcuts.first { $0.value == shortcut }?.key
    }

    /// Assigns `shortcut` to `id`, taking it away from any other source. nil clears.
    func set(_ shortcut: Shortcut?, for id: String) {
        if let shortcut {
            shortcuts = shortcuts.filter { $0.value != shortcut }
        }
        shortcuts[id] = shortcut
        saveShortcuts()
        onChange?()
    }

    private func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

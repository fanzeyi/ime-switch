import AppKit
import Carbon

struct InputSource {
    let id: String
    let name: String
    let isKeyboardLayout: Bool
    /// Short badge text, as in the system menu bar (e.g. "简拼", "あ", "DE").
    let label: String
}

@MainActor
final class InputSourceManager {
    private(set) var sources: [InputSource] = []

    /// Called on the main thread whenever the selected source changes, from any cause.
    var onSelectionChanged: ((String) -> Void)?
    /// Called on the main thread when the set of enabled sources changes.
    var onSourcesChanged: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let id = self.currentID else { return }
                self.onSelectionChanged?(id)
            }
        })
        observers.append(center.addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                self.onSourcesChanged?()
            }
        })
    }

    var currentID: String? {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return Self.string(current, kTISPropertyInputSourceID)
    }

    func source(withID id: String) -> InputSource? {
        sources.first { $0.id == id }
    }

    func refresh() {
        let raw = Self.selectableSources().map { tis in
            let id = Self.string(tis, kTISPropertyInputSourceID) ?? ""
            let name = Self.string(tis, kTISPropertyLocalizedName) ?? ""
            let labels = Self.property(tis, Self.iconLabelsKey) as? [String: Any]
            return (
                id: id,
                name: name,
                isLayout: Self.string(tis, kTISPropertyInputSourceType) == (kTISTypeKeyboardLayout as String),
                primary: Self.labelOverrides[id] ?? labels?["Primary"] as? String ?? Self.fallbackLabel(name),
                secondary: labels?["Secondary"] as? String,
                language: (Self.property(tis, kTISPropertyInputSourceLanguages) as? [String])?.first
            )
        }

        // The system disambiguates sources that share a badge, e.g. Simplified and
        // Traditional Pinyin are both "拼音" but show as "简拼" and "繁拼".
        let counts = Dictionary(grouping: raw, by: \.primary).mapValues(\.count)
        sources = raw.map { source in
            var label = source.primary
            if counts[source.primary, default: 0] > 1 {
                if let prefix = Self.chineseScriptPrefix(source.language), let first = label.first {
                    label = prefix + String(first)
                } else if let secondary = source.secondary {
                    label += secondary
                }
            }
            return InputSource(id: source.id, name: source.name, isKeyboardLayout: source.isLayout, label: label)
        }
    }

    /// Not in the public headers, but exported by HIToolbox and what the system menu
    /// bar uses for its badges: a dictionary with "Primary" and optional "Secondary".
    private static let iconLabelsKey = "TISPropertyInputSourceIconLabels" as CFString

    /// Cases where the menu bar shows something other than the source's own label.
    private static let labelOverrides = [
        "com.apple.keylayout.US": "A",
    ]

    private static func fallbackLabel(_ name: String) -> String {
        String(name.prefix(2))
    }

    private static func chineseScriptPrefix(_ language: String?) -> String? {
        switch language {
        case "zh-Hans": "简"
        case "zh-Hant": "繁"
        default: nil
        }
    }

    @discardableResult
    func select(_ id: String) -> Bool {
        guard let tis = Self.selectableSources().first(where: { Self.string($0, kTISPropertyInputSourceID) == id }) else {
            return false
        }
        if currentID == id { return true }
        let status = TISSelectInputSource(tis)
        if status != noErr { return false }
        // TISSelectInputSource occasionally reports success for CJK input modes without
        // actually switching; one retry on the next runloop turn covers the common case.
        if currentID != id {
            DispatchQueue.main.async { TISSelectInputSource(tis) }
        }
        return true
    }

    // MARK: - TIS helpers

    private static func selectableSources() -> [TISInputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        property(source, key) as? String
    }
}

import AppKit
import Carbon

struct InputSource {
    let id: String
    let name: String
    let icon: NSImage?

    /// Short label shown in the HUD, mirroring the system switcher where we know it.
    var shortLabel: String {
        if let label = Self.knownLabels[id] { return label }
        if id.hasPrefix("com.apple.keylayout.") { return String(name.prefix(1)) }
        return String(name.prefix(2))
    }

    private static let knownLabels: [String: String] = [
        "com.apple.keylayout.ABC": "A",
        "com.apple.keylayout.US": "A",
        "com.apple.inputmethod.SCIM.ITABC": "简拼",
        "com.apple.inputmethod.SCIM.Shuangpin": "简双",
        "com.apple.inputmethod.SCIM.WBX": "五笔",
        "com.apple.inputmethod.SCIM.WBH": "五笔",
        "com.apple.inputmethod.TCIM.Pinyin": "繁拼",
        "com.apple.inputmethod.TCIM.Shuangpin": "繁双",
        "com.apple.inputmethod.TCIM.Zhuyin": "注音",
        "com.apple.inputmethod.TCIM.ZhuyinEten": "注音",
        "com.apple.inputmethod.TCIM.Cangjie": "倉頡",
        "com.apple.inputmethod.TCIM.Jianyi": "速成",
        "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese": "あ",
        "com.apple.inputmethod.Kotoeri.KanaTyping.Japanese": "あ",
        "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana": "ア",
        "com.apple.inputmethod.Kotoeri.KanaTyping.Japanese.Katakana": "ア",
        "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman": "A",
        "com.apple.inputmethod.Korean.2SetKorean": "한",
        "com.apple.inputmethod.Korean.3SetKorean": "한",
    ]
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
        sources = Self.selectableSources().map { tis in
            InputSource(
                id: Self.string(tis, kTISPropertyInputSourceID) ?? "",
                name: Self.string(tis, kTISPropertyLocalizedName) ?? "",
                icon: Self.icon(tis)
            )
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

    private static func icon(_ source: TISInputSource) -> NSImage? {
        if let url = property(source, kTISPropertyIconImageURL) as? URL, let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        return nil
    }
}

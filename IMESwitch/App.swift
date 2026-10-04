import AppKit
import ServiceManagement

@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let inputSources = InputSourceManager()
    private let mru = MRUStore()
    private let tap = HotkeyTap()
    private let hud = SwitcherHUD()
    private let onboarding = OnboardingWindow()
    private let shortcuts = ShortcutStore()
    private lazy var shortcutsWindow = ShortcutsWindow(store: shortcuts)

    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    // Cycle state
    private var candidates: [String] = []
    private var index = 0
    private var hudVisible = false
    private var pendingHUD: DispatchWorkItem?

    /// A tap released within this interval switches without ever showing the HUD.
    private static let hudDelay: TimeInterval = 0.15

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        syncMRU()
        inputSources.onSelectionChanged = { [weak self] id in
            self?.mru.promote(id)
            self?.updateStatusIcon()
        }
        inputSources.onSourcesChanged = { [weak self] in
            guard let self else { return }
            self.syncMRU()
            self.updateStatusIcon()
            self.shortcutsWindow.update(sources: self.inputSources.sources)
        }
        updateStatusIcon()
        tap.handler = { [weak self] event in self?.handle(event) }
        tap.shortcuts = Set(shortcuts.shortcuts.values)
        shortcuts.onChange = { [weak self] in
            guard let self else { return }
            self.tap.shortcuts = Set(self.shortcuts.shortcuts.values)
        }
        shortcutsWindow.onRecordingChanged = { [weak self] recording in
            self?.tap.shortcutsPaused = recording
        }

        startTapWhenTrusted()
        if !OnboardingWindow.isComplete {
            onboarding.show()
        }
    }

    // MARK: - Switching

    private func syncMRU() {
        mru.reconcile(available: inputSources.sources.map(\.id))
        if let current = inputSources.currentID { mru.promote(current) }
    }

    private func handle(_ event: HotkeyTap.Event) {
        switch event {
        case let .press(first, reverse):
            if first {
                syncMRU()
                candidates = mru.order
                index = 0
            }
            guard candidates.count > 1 else { return }
            index = (index + (reverse ? -1 : 1) + candidates.count) % candidates.count
            if first {
                let work = DispatchWorkItem { [weak self] in self?.showHUD() }
                pendingHUD = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.hudDelay, execute: work)
            } else if hudVisible {
                hud.move(to: index)
            } else {
                showHUD()
            }

        case .commit:
            let target = candidates.indices.contains(index) ? candidates[index] : nil
            endCycle()
            hud.dismiss()
            if let target, inputSources.select(target) {
                mru.promote(target)
            }

        case .cancel:
            endCycle()
            hud.hide()

        case let .shortcut(shortcut):
            if let id = shortcuts.sourceID(for: shortcut), inputSources.select(id) {
                mru.promote(id)
            }
        }
    }

    private func showHUD() {
        pendingHUD?.cancel()
        pendingHUD = nil
        guard !candidates.isEmpty else { return }
        let items = candidates.compactMap { inputSources.source(withID: $0) }
        guard items.count == candidates.count else { return }
        hud.showStrip(items: items, selected: index, caret: CaretLocator.caretRect())
        hudVisible = true
    }

    private func endCycle() {
        pendingHUD?.cancel()
        pendingHUD = nil
        hudVisible = false
        candidates = []
        index = 0
    }

    // MARK: - Permissions

    private func startTapWhenTrusted() {
        if Permissions.isAccessibilityTrusted, tap.start() { return }
        // Onboarding asks for the permission; just wait for it to be granted.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Permissions.isAccessibilityTrusted, self.tap.start() else { return }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    // MARK: - Menu

    private func updateStatusIcon() {
        if let id = inputSources.currentID, let source = inputSources.source(withID: id) {
            statusItem.button?.image = BadgeImage.make(label: source.label, outlined: source.isKeyboardLayout)
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "IMESwitch")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let current = inputSources.currentID
        for source in inputSources.sources {
            let item = NSMenuItem(title: source.name, action: #selector(selectSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            item.state = source.id == current ? .on : .off
            item.attributedTitle = Self.menuTitle(source)
            if let shortcut = shortcuts.shortcuts[source.id], let key = shortcut.menuKeyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = shortcut.menuModifierMask
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if !OnboardingWindow.isComplete {
            let item = NSMenuItem(title: String(localized: "⚠️ Finish Setup…"), action: #selector(showOnboarding), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let shortcutsItem = NSMenuItem(title: String(localized: "Configure Shortcuts…"), action: #selector(showShortcuts), keyEquivalent: "")
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)

        let login = NSMenuItem(title: String(localized: "Launch at Login"), action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit IMESwitch"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// Menus on current macOS don't draw `NSMenuItem.image`, so the badge goes into the
    /// title as a text attachment, drawn in the label color like the system Input menu.
    private static func menuTitle(_ source: InputSource) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let badge = BadgeImage.make(label: source.label, color: .labelColor)
        let attachment = NSTextAttachment()
        attachment.image = badge
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - badge.size.height) / 2,
                                   width: badge.size.width, height: badge.size.height)
        let title = NSMutableAttributedString(attachment: attachment)
        title.append(NSAttributedString(string: "  " + source.name, attributes: [.font: font]))
        return title
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if inputSources.select(id) { mru.promote(id) }
    }

    @objc private func showOnboarding() {
        onboarding.show()
    }

    @objc private func showShortcuts() {
        shortcutsWindow.show(sources: inputSources.sources)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

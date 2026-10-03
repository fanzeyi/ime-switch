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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "IMESwitch")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        syncMRU()
        inputSources.onSelectionChanged = { [weak self] id in self?.mru.promote(id) }
        inputSources.onSourcesChanged = { [weak self] in self?.syncMRU() }
        tap.handler = { [weak self] event in self?.handle(event) }

        startTapWhenTrusted()
        warnAboutConflictingShortcuts()
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
                hud.update(selected: index)
            } else {
                showHUD()
            }

        case .commit:
            let target = candidates.indices.contains(index) ? candidates[index] : nil
            endCycle()
            if let target, inputSources.select(target) {
                mru.promote(target)
            }

        case .cancel:
            endCycle()
        }
    }

    private func showHUD() {
        pendingHUD?.cancel()
        pendingHUD = nil
        guard !candidates.isEmpty else { return }
        let items = candidates.compactMap { inputSources.source(withID: $0) }
        guard items.count == candidates.count else { return }
        hud.show(items: items, selected: index, near: CaretLocator.caretRect())
        hudVisible = true
    }

    private func endCycle() {
        pendingHUD?.cancel()
        pendingHUD = nil
        hud.hide()
        hudVisible = false
        candidates = []
        index = 0
    }

    // MARK: - Permissions

    private func startTapWhenTrusted() {
        if Permissions.isAccessibilityTrusted, tap.start() { return }
        Permissions.requestAccessibility()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Permissions.isAccessibilityTrusted, self.tap.start() else { return }
                self.permissionTimer?.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    private func warnAboutConflictingShortcuts() {
        let conflicts = Permissions.conflictingSystemShortcuts()
        guard !conflicts.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "系统快捷键仍占用 ⌘Space"
        alert.informativeText = "请在“系统设置 → 键盘 → 键盘快捷键”中关闭以下快捷键，否则会与 IMESwitch 冲突：\n\n"
            + conflicts.map { "• \($0)" }.joined(separator: "\n")
        alert.addButton(withTitle: "打开键盘设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openKeyboardShortcutSettings()
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let current = inputSources.currentID
        for source in inputSources.sources {
            let item = NSMenuItem(title: source.name, action: #selector(selectSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            item.state = source.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if !tap.isRunning {
            let item = NSMenuItem(title: "⚠️ 需要辅助功能权限…", action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let conflicts = Permissions.conflictingSystemShortcuts()
        if !conflicts.isEmpty {
            let item = NSMenuItem(title: "⚠️ 系统快捷键冲突：\(conflicts.joined(separator: "、"))…",
                                  action: #selector(openKeyboardSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 IMESwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if inputSources.select(id) { mru.promote(id) }
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openKeyboardSettings() {
        Permissions.openKeyboardShortcutSettings()
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

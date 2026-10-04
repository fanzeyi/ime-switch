import AppKit
import CoreGraphics

/// Intercepts the switcher shortcut (⌘Space by default) system-wide and reports press /
/// release / cancel, the way ⌘Tab works: holding its modifiers while pressing its key
/// repeatedly advances, adding ⇧ goes back, releasing a modifier commits, Esc cancels.
/// Also catches the per-input-source shortcuts.
@MainActor
final class HotkeyTap {
    enum Event {
        /// The switcher pressed. `first` is true for the press that starts a cycle.
        case press(first: Bool, reverse: Bool)
        case commit
        case cancel
        /// One of `shortcuts` was pressed.
        case shortcut(Shortcut)
    }

    var handler: ((Event) -> Void)?
    var switcher = Shortcut.defaultSwitcher
    var shortcuts: Set<Shortcut> = []
    /// Lets the switcher and shortcuts through while the user records a new one.
    var shortcutsPaused = false

    nonisolated static let spaceKey: Int64 = 49
    private static let escapeKey = Shortcut.escapeKey
    private static let relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var cycling = false
    /// Key codes whose keyDown we swallowed, so the matching keyUp is swallowed too.
    private var swallowedKeys: Set<Int64> = []

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: refcon
        ) else {
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
        cycling = false
        swallowedKeys.removeAll()
    }

    /// Returns true if the event should be swallowed.
    fileprivate func handle(type: CGEventType, key: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false

        case .keyDown:
            let mods = flags.intersection(Self.relevantModifiers)
            if key == switcher.keyCode, !shortcutsPaused || cycling,
               mods == switcher.flags || (cycling && mods == switcher.reversed.flags) {
                let first = !cycling
                cycling = true
                swallowedKeys.insert(key)
                handler?(.press(first: first, reverse: mods.contains(.maskShift)))
                return true
            }
            if cycling, key == Self.escapeKey {
                cycling = false
                swallowedKeys.insert(key)
                handler?(.cancel)
                return true
            }
            let shortcut = Shortcut(keyCode: key, flags: flags)
            if !cycling, !shortcutsPaused, shortcuts.contains(shortcut) {
                swallowedKeys.insert(key)
                if !isRepeat { handler?(.shortcut(shortcut)) }
                return true
            }
            return false

        case .keyUp:
            return swallowedKeys.remove(key) != nil

        case .flagsChanged:
            if cycling, !flags.contains(switcher.flags) {
                cycling = false
                handler?(.commit)
            }
            return false

        default:
            return false
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated { tap.handle(type: type, key: key, flags: flags, isRepeat: isRepeat) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

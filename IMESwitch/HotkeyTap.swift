import AppKit
import CoreGraphics

/// Intercepts cmd+space system-wide and reports press / release / cancel, the way
/// cmd+tab works: holding cmd while pressing space repeatedly advances, releasing
/// cmd commits, Esc cancels.
@MainActor
final class HotkeyTap {
    enum Event {
        /// Space pressed with cmd held. `first` is true for the press that starts a cycle.
        case press(first: Bool, reverse: Bool)
        case commit
        case cancel
    }

    var handler: ((Event) -> Void)?

    private static let spaceKey: Int64 = 49
    private static let escapeKey: Int64 = 53
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
    fileprivate func handle(type: CGEventType, key: Int64, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false

        case .keyDown:
            let mods = flags.intersection(Self.relevantModifiers)
            if key == Self.spaceKey, mods == .maskCommand || (cycling && mods == [.maskCommand, .maskShift]) {
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
            return false

        case .keyUp:
            return swallowedKeys.remove(key) != nil

        case .flagsChanged:
            if cycling, !flags.contains(.maskCommand) {
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
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated { tap.handle(type: type, key: key, flags: flags) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

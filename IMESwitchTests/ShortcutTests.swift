import AppKit
import Testing

private enum Key {
    static let a: Int64 = 0
    static let one: Int64 = 18
    static let returnKey: Int64 = 36
    static let space: Int64 = 49
    static let escape: Int64 = 53
    static let f1: Int64 = 122
    static let f5: Int64 = 96
    static let leftArrow: Int64 = 123
}

struct ShortcutTests {
    private let commandSpace = Shortcut(keyCode: Key.space, flags: .maskCommand)

    @Test func keepsOnlyModifierFlags() {
        let shortcut = Shortcut(keyCode: Key.f5, flags: [.maskCommand, .maskSecondaryFn, .maskAlphaShift])
        #expect(shortcut.flags == .maskCommand)
        #expect(shortcut == Shortcut(keyCode: Key.f5, flags: .maskCommand))
    }

    @Test func defaultSwitcherIsCommandSpace() {
        #expect(Shortcut.defaultSwitcher == commandSpace)
    }

    @Test func reversedAddsShift() {
        #expect(commandSpace.reversed == Shortcut(keyCode: Key.space, flags: [.maskCommand, .maskShift]))
        #expect(commandSpace.reversed.reversed == commandSpace.reversed)
    }

    @Test func roundTripsThroughCodable() throws {
        let shortcut = Shortcut(keyCode: Key.one, flags: [.maskControl, .maskAlternate])
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == shortcut)
    }

    // MARK: - Display

    @Test(arguments: [
        (Shortcut(keyCode: Key.space, flags: .maskCommand), "⌘Space"),
        (Shortcut(keyCode: Key.space, flags: [.maskCommand, .maskShift, .maskAlternate, .maskControl]), "⌃⌥⇧⌘Space"),
        (Shortcut(keyCode: Key.f5, flags: .maskShift), "⇧F5"),
        (Shortcut(keyCode: Key.f1, flags: []), "F1"),
        (Shortcut(keyCode: Key.returnKey, flags: .maskControl), "⌃↩"),
        (Shortcut(keyCode: Key.leftArrow, flags: .maskAlternate), "⌥←"),
    ])
    func displayString(_ shortcut: Shortcut, _ expected: String) {
        #expect(shortcut.displayString == expected)
    }

    @Test func menuKeyEquivalents() {
        #expect(Shortcut(keyCode: Key.space, flags: .maskCommand).menuKeyEquivalent == " ")
        #expect(Shortcut(keyCode: Key.f1, flags: []).menuKeyEquivalent == String(Character(UnicodeScalar(NSF1FunctionKey)!)))
        #expect(Shortcut(keyCode: Key.leftArrow, flags: []).menuKeyEquivalent == String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        #expect(Shortcut(keyCode: Key.one, flags: [.maskControl, .maskShift]).menuModifierMask == [.control, .shift])
    }

    // MARK: - Per-source shortcuts

    @Test func switcherIsReserved() {
        #expect(commandSpace.problem(switcher: commandSpace) == .reserved)
    }

    @Test func switcherReversedIsAllowed() {
        // ⌘⇧Space only goes backwards while cycling, so a source can have it otherwise.
        #expect(commandSpace.reversed.problem(switcher: commandSpace) != .reserved)
    }

    @Test func otherSwitcherFreesCommandSpace() {
        let optionSpace = Shortcut(keyCode: Key.space, flags: .maskAlternate)
        #expect(commandSpace.problem(switcher: optionSpace) != .reserved)
        #expect(optionSpace.problem(switcher: optionSpace) == .reserved)
    }

    @Test(arguments: [
        Shortcut(keyCode: Key.a, flags: []),
        Shortcut(keyCode: Key.a, flags: .maskShift),
        Shortcut(keyCode: Key.space, flags: []),
    ])
    func plainKeysNeedModifier(_ shortcut: Shortcut) {
        #expect(shortcut.problem(switcher: commandSpace) == .needsModifier)
    }

    @Test(arguments: [
        Shortcut(keyCode: Key.f5, flags: []),
        Shortcut(keyCode: Key.f1, flags: .maskShift),
        Shortcut(keyCode: Key.one, flags: [.maskControl, .maskAlternate]),
    ])
    func functionKeysAndModifiedKeysAreAccepted(_ shortcut: Shortcut) {
        // usedBySystem depends on this Mac's keyboard shortcuts, so only rule out the others.
        let problem = shortcut.problem(switcher: commandSpace)
        #expect(problem != .needsModifier && problem != .reserved)
    }

    @Test func systemShortcutsAreRejected() throws {
        let taken = try #require(
            Shortcut.systemShortcuts().first {
                $0 != commandSpace && !$0.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
            },
            "this Mac has no enabled system shortcut with ⌘, ⌃ or ⌥"
        )
        #expect(taken.problem(switcher: commandSpace) == .usedBySystem)
    }

    // MARK: - Switcher

    @Test(arguments: [
        Shortcut(keyCode: Key.space, flags: .maskCommand),
        Shortcut(keyCode: Key.space, flags: .maskAlternate),
        Shortcut(keyCode: Key.space, flags: [.maskControl, .maskAlternate]),
        Shortcut(keyCode: Key.a, flags: .maskControl),
    ])
    func validSwitchers(_ shortcut: Shortcut) {
        #expect(shortcut.switcherProblem == nil)
    }

    @Test func switcherNeedsHeldModifier() {
        #expect(Shortcut(keyCode: Key.space, flags: []).switcherProblem == .needsHeldModifier)
        #expect(Shortcut(keyCode: Key.f5, flags: []).switcherProblem == .needsHeldModifier)
    }

    @Test func switcherCantIncludeShift() {
        #expect(Shortcut(keyCode: Key.space, flags: [.maskCommand, .maskShift]).switcherProblem == .includesShift)
    }

    @Test func switcherCantBeEscape() {
        #expect(Shortcut(keyCode: Key.escape, flags: .maskCommand).switcherProblem == .escape)
    }
}

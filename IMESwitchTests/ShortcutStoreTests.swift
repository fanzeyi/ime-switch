import CoreGraphics
import Foundation
import Testing

@MainActor
struct ShortcutStoreTests {
    private let us = "com.apple.keylayout.US"
    private let pinyin = "com.apple.inputmethod.SCIM.ITABC"
    private let controlOptionOne = Shortcut(keyCode: 18, flags: [.maskControl, .maskAlternate])
    private let controlOptionTwo = Shortcut(keyCode: 19, flags: [.maskControl, .maskAlternate])
    private let optionSpace = Shortcut(keyCode: 49, flags: .maskAlternate)

    @Test func startsEmptyWithDefaultSwitcher() {
        let store = ShortcutStore(defaults: makeTestDefaults())
        #expect(store.shortcuts.isEmpty)
        #expect(store.switcher == .defaultSwitcher)
    }

    @Test func setAndClear() {
        let store = ShortcutStore(defaults: makeTestDefaults())
        store.set(controlOptionOne, for: us)
        #expect(store.shortcuts[us] == controlOptionOne)
        #expect(store.sourceID(for: controlOptionOne) == us)
        store.set(nil, for: us)
        #expect(store.shortcuts[us] == nil)
        #expect(store.sourceID(for: controlOptionOne) == nil)
    }

    @Test func shortcutMovesToTheLatestSource() {
        let store = ShortcutStore(defaults: makeTestDefaults())
        store.set(controlOptionOne, for: us)
        store.set(controlOptionOne, for: pinyin)
        #expect(store.shortcuts == [pinyin: controlOptionOne])
    }

    @Test func settingSwitcherClearsSourceOnSameKeys() {
        let store = ShortcutStore(defaults: makeTestDefaults())
        store.set(optionSpace, for: us)
        store.set(optionSpace.reversed, for: pinyin)
        store.setSwitcher(optionSpace)
        #expect(store.switcher == optionSpace)
        // The ⇧ variant stays: it only goes backwards while cycling.
        #expect(store.shortcuts == [pinyin: optionSpace.reversed])
    }

    @Test func notifiesOnChange() {
        let store = ShortcutStore(defaults: makeTestDefaults())
        var changes = 0
        store.onChange = { changes += 1 }
        store.set(controlOptionOne, for: us)
        store.setSwitcher(optionSpace)
        #expect(changes == 2)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeTestDefaults()
        let first = ShortcutStore(defaults: defaults)
        first.set(controlOptionOne, for: us)
        first.set(controlOptionTwo, for: pinyin)
        first.setSwitcher(optionSpace)

        let second = ShortcutStore(defaults: defaults)
        #expect(second.shortcuts == [us: controlOptionOne, pinyin: controlOptionTwo])
        #expect(second.switcher == optionSpace)
    }

    @Test func excludeAndInclude() {
        let defaults = makeTestDefaults()
        let store = ShortcutStore(defaults: defaults)
        var changes = 0
        store.onChange = { changes += 1 }
        store.setExcluded(true, for: us)
        store.setExcluded(true, for: us) // no change
        #expect(store.excluded == [us])
        #expect(ShortcutStore(defaults: defaults).excluded == [us])
        store.setExcluded(false, for: us)
        #expect(store.excluded.isEmpty)
        #expect(changes == 2)
    }

    @Test func invalidSavedSwitcherFallsBackToDefault() throws {
        let defaults = makeTestDefaults()
        let shiftSpace = Shortcut(keyCode: 49, flags: .maskShift)
        defaults.set(try JSONEncoder().encode(shiftSpace), forKey: "SwitcherShortcut")
        #expect(ShortcutStore(defaults: defaults).switcher == .defaultSwitcher)
    }
}

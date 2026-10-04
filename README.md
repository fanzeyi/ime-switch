# IMESwitch

A menu bar app that replaces macOS's ⌘Space input source switching with cmd+tab-style MRU behavior.

- **Tap ⌘Space** → switch to the previously used input source. Tap again to come back.
- **Hold ⌘, press Space repeatedly** → walk through input sources in most-recently-used order, with a HUD near the text caret. Release ⌘ to commit; the chosen source moves to the front, so the next tap returns to where you came from.
- **⌘⇧Space** while cycling goes backwards, **Esc** cancels.
- **Per-source shortcuts** (menu → Configure Shortcuts…) switch straight to one input source, e.g. ⌃⌥1 for ABC. They need ⌘, ⌃ or ⌥, or can be a bare function key; shortcuts macOS already uses are rejected.
- Switching from the menu bar or any other way also updates the MRU order.
- **Show Emoji & Symbols** in the menu opens the Character Viewer in the app you're typing in, by pressing that app's own Edit → Emoji & Symbols item, so it follows any custom shortcut for it.
- The menu bar badge mirrors the system one (简拼, あ, DE, РУ, …), using the labels macOS itself provides for each input source.
- UI in English, Simplified Chinese, Traditional Chinese and Japanese.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run       # build and launch the dev app, "IMESwitch Dev"
make dist      # notarized build for distribution (see below)
make install   # copy the `make dist` build to /Applications and launch
```

The dev app (Debug configuration) has its own bundle ID, `fan.zeyi.IMESwitch.dev`, so it gets its own Accessibility grant and settings and never invalidates the installed app's grant. Only one can own ⌘Space at a time, so `make run` quits the installed app; restart it with `open /Applications/IMESwitch.app`.

## Setup

1. **Disable the system shortcut**: System Settings → Keyboard → Keyboard Shortcuts → Input Sources, turn off "Select the previous input source" (and Spotlight, if it is still on ⌘Space). The app warns at launch if these are still bound.
2. **Grant Accessibility**: System Settings → Privacy & Security → Accessibility → enable IMESwitch. Needed for the event tap that intercepts ⌘Space and for locating the caret.

A setup window walks through both steps on first launch, and the menu offers "Finish Setup…" while either is missing.

Dev builds are signed with an Apple Development certificate (team `U75D75QN8A` in `project.yml`), so the designated requirement stays stable across rebuilds and the Accessibility grant survives.

## Distribute

`make dist` builds a universal binary signed with Developer ID, notarizes it and staples the ticket, producing `build/IMESwitch.zip` that runs on other Macs without Gatekeeper warnings. Store notarization credentials in the keychain once first:

```sh
xcrun notarytool store-credentials IMESwitch --apple-id <apple-id> --team-id U75D75QN8A
```

Recipients still need to do the two setup steps above.

## Layout

| File | Role |
| --- | --- |
| `IMESwitch/App.swift` | Entry point, status menu, cycle state machine |
| `IMESwitch/HotkeyTap.swift` | `CGEventTap` that turns ⌘Space / ⌘ release / Esc into press / commit / cancel, and catches per-source shortcuts |
| `IMESwitch/InputSourceManager.swift` | Text Input Sources (TIS) listing, selection, change notifications |
| `IMESwitch/MRUStore.swift` | MRU order, persisted in `UserDefaults` |
| `IMESwitch/SwitcherHUD.swift` | Non-activating capsule panel |
| `IMESwitch/CaretLocator.swift` | Caret position via the Accessibility API, falling back to screen center |
| `IMESwitch/Shortcut.swift` | Per-source shortcuts: key names, validation and storage |
| `IMESwitch/ShortcutsWindow.swift` | Window for recording per-source shortcuts |
| `IMESwitch/EmojiPicker.swift` | Opens Emoji & Symbols in the frontmost app through its menu |
| `IMESwitch/Permissions.swift` | Accessibility trust and system shortcut conflict detection |
| `IMESwitch/OnboardingWindow.swift` | First-run setup: Accessibility access and the system ⌘Space shortcut, with live status |
| `IMESwitch/BadgeImage.swift` | System-style input source badge for the menu bar, and the label typography shared with the HUD |
| `IMESwitch/AppIcon.icon` | App icon in Icon Composer format (Liquid Glass); edit with Xcode's Icon Composer |
| `IMESwitch/Localizable.xcstrings` | UI translations |

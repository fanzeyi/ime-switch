# IMESwitch

A menu bar app that replaces macOS's ⌘Space input source switching with cmd+tab-style MRU behavior.

- **Tap ⌘Space** → switch to the previously used input source. Tap again to come back.
- **Hold ⌘, press Space repeatedly** → walk through input sources in most-recently-used order, with a HUD near the text caret. Release ⌘ to commit; the chosen source moves to the front, so the next tap returns to where you came from.
- **⌘⇧Space** while cycling goes backwards, **Esc** cancels.
- Switching from the menu bar or any other way also updates the MRU order.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run       # generate project, build Release, launch
make install   # copy to /Applications and launch
```

## Setup

1. **Disable the system shortcut**: System Settings → Keyboard → Keyboard Shortcuts → Input Sources, turn off "Select the previous input source" (and Spotlight, if it is still on ⌘Space). The app warns at launch if these are still bound.
2. **Grant Accessibility**: System Settings → Privacy & Security → Accessibility → enable IMESwitch. Needed for the event tap that intercepts ⌘Space and for locating the caret.

The app is signed with an Apple Development certificate (team `U75D75QN8A` in `project.yml`), so its designated requirement stays stable across rebuilds and the Accessibility grant survives. After switching from the earlier ad-hoc build, remove the old IMESwitch entry from the Accessibility list and add it again once.

## Layout

| File | Role |
| --- | --- |
| `IMESwitch/App.swift` | Entry point, status menu, cycle state machine |
| `IMESwitch/HotkeyTap.swift` | `CGEventTap` that turns ⌘Space / ⌘ release / Esc into press / commit / cancel |
| `IMESwitch/InputSourceManager.swift` | Text Input Sources (TIS) listing, selection, change notifications |
| `IMESwitch/MRUStore.swift` | MRU order, persisted in `UserDefaults` |
| `IMESwitch/SwitcherHUD.swift` | Non-activating capsule panel |
| `IMESwitch/CaretLocator.swift` | Caret position via the Accessibility API, falling back to screen center |
| `IMESwitch/Permissions.swift` | Accessibility trust and system shortcut conflict detection |

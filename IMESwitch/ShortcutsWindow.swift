import AppKit
import SwiftUI

/// Records the switcher shortcut, and lists the enabled input sources, each with a recorder
/// for a shortcut that switches straight to it.
@MainActor
final class ShortcutsWindow {
    private let model: ShortcutsModel
    private var window: NSWindow?

    init(store: ShortcutStore) {
        model = ShortcutsModel(store: store)
    }

    /// Called when recording starts or stops, so the event tap can let keys through.
    var onRecordingChanged: ((Bool) -> Void)? {
        get { model.onRecordingChanged }
        set { model.onRecordingChanged = newValue }
    }

    func update(sources: [InputSource]) {
        model.sources = sources
    }

    func show(sources: [InputSource]) {
        model.sources = sources
        if window == nil {
            let hosting = NSHostingController(rootView: ShortcutsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Shortcuts")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.stopRecording() }
            }
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.stopRecording() }
            }
            self.window = window
            window.center()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class ShortcutsModel: ObservableObject {
    /// Recording ID for the switcher; input source IDs are reverse-DNS, so it can't clash.
    static let switcherID = "switcher"

    let store: ShortcutStore
    @Published var sources: [InputSource] = []
    @Published private(set) var recordingID: String?
    @Published private(set) var message: LocalizedStringKey?

    var onRecordingChanged: ((Bool) -> Void)?
    private var monitor: Any?

    init(store: ShortcutStore) {
        self.store = store
    }

    func toggleRecording(_ id: String) {
        if recordingID == id {
            stopRecording()
        } else {
            startRecording(id)
        }
    }

    private func startRecording(_ id: String) {
        stopRecording()
        recordingID = id
        onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
    }

    func stopRecording() {
        guard recordingID != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingID = nil
        message = nil
        onRecordingChanged?(false)
    }

    private func record(_ event: NSEvent) {
        guard let id = recordingID, !event.isARepeat else { return }
        let shortcut = Shortcut(event: event)
        if shortcut.flags.isEmpty {
            switch shortcut.keyCode {
            case Shortcut.escapeKey:
                stopRecording()
                return
            case 51, 117: // Delete, Forward Delete
                clear(id)
                return
            default:
                break
            }
        }
        if id == Self.switcherID {
            recordSwitcher(shortcut)
            return
        }
        switch shortcut.problem(switcher: store.switcher) {
        case .needsModifier:
            reject("Use ⌘, ⌃ or ⌥ with the key, or a function key.")
        case .reserved:
            reject("\(store.switcher.displayString) is already used to cycle input sources.")
        case .usedBySystem:
            reject("macOS already uses this shortcut. Pick another, or turn it off in Keyboard Shortcuts.")
        case nil:
            store.set(shortcut, for: id)
            stopRecording()
        }
    }

    private func recordSwitcher(_ shortcut: Shortcut) {
        switch shortcut.switcherProblem {
        case .needsHeldModifier:
            reject("Use ⌘, ⌃ or ⌥ with the key, to hold down while cycling.")
        case .includesShift:
            reject("⇧ is left for cycling backwards.")
        case .escape:
            reject("Esc is left for cancelling.")
        case nil:
            store.setSwitcher(shortcut)
            stopRecording()
        }
    }

    private func reject(_ reason: LocalizedStringKey) {
        message = reason
        NSSound.beep()
    }

    /// Clears an input source's shortcut, or resets the switcher to ⌘Space.
    func clear(_ id: String) {
        stopRecording()
        if id == Self.switcherID {
            store.setSwitcher(.defaultSwitcher)
        } else {
            store.set(nil, for: id)
        }
    }
}

private struct ShortcutsView: View {
    @ObservedObject var model: ShortcutsModel
    @ObservedObject var store: ShortcutStore

    init(model: ShortcutsModel) {
        self.model = model
        store = model.store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Switcher", footer: footer(for: ShortcutsModel.switcherID,
                                               idle: "Hold the modifiers and press the key repeatedly to cycle; add ⇧ to go back.")) {
                switcherRow
                Divider().padding(.leading, 12)
                cycleThroughRow
            }
            section("Input Sources", footer: footer(for: nil,
                                                    idle: "Press a shortcut anywhere to switch straight to that input source.")) {
                ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 { Divider().padding(.leading, 46) }
                    row(source)
                }
            } accessory: {
                Button("Edit…") {
                    model.stopRecording()
                    Permissions.openInputSourceSettings()
                }
                .buttonStyle(.link)
                .help("Edit Input Sources…")
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// A titled, rounded group like System Settings, with a caption below.
    private func section<Content: View, Accessory: View>(
        _ title: LocalizedStringKey,
        footer: some View,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                accessory()
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0, content: content)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            footer
                .padding(.horizontal, 4)
        }
    }

    /// The section's description, or while recording in it, how to finish or why the last
    /// shortcut was rejected. `recordingID` nil stands for any input source.
    private func footer(for recordingID: String?, idle: LocalizedStringKey) -> some View {
        var recording = false
        if let current = model.recordingID {
            recording = recordingID.map { current == $0 } ?? (current != ShortcutsModel.switcherID)
        }
        let hint: LocalizedStringKey = recordingID == ShortcutsModel.switcherID
            ? "Type the new shortcut. Esc cancels, Delete resets to \(Shortcut.defaultSwitcher.displayString)."
            : "Type the new shortcut. Esc cancels, Delete clears."
        let rejected = recording && model.message != nil
        return Text(rejected ? model.message! : recording ? hint : idle)
            .font(.caption)
            .foregroundStyle(rejected ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var switcherRow: some View {
        let id = ShortcutsModel.switcherID
        let conflicts = model.recordingID == id ? [] : Permissions.conflictingSystemShortcuts()
        return HStack(spacing: 12) {
            Text("Switch Input Sources")
            Spacer(minLength: 12)
            if !conflicts.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("macOS uses this shortcut too: \(conflicts.formatted(.list(type: .and))). Turn it off in Keyboard Shortcuts.")
            }
            ShortcutField(
                shortcut: store.switcher,
                isRecording: model.recordingID == id,
                canClear: store.switcher != .defaultSwitcher,
                clearHelp: "Reset to \(Shortcut.defaultSwitcher.displayString)",
                toggle: { model.toggleRecording(id) },
                clear: { model.clear(id) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Which sources the switcher cycles through; the rest stay reachable by shortcut.
    private var cycleThroughRow: some View {
        let included = model.sources.filter { !store.excluded.contains($0.id) }
        return HStack(spacing: 12) {
            Text("Cycle Through")
            Spacer(minLength: 12)
            Menu {
                ForEach(model.sources, id: \.id) { source in
                    Toggle(source.name, isOn: Binding(
                        get: { !store.excluded.contains(source.id) },
                        set: { store.setExcluded(!$0, for: source.id) }
                    ))
                }
            } label: {
                if included.count == model.sources.count {
                    Text("All Input Sources")
                } else {
                    Text("\(included.count) of \(model.sources.count)")
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ source: InputSource) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: BadgeImage.make(label: source.label, outlined: source.isKeyboardLayout, color: .labelColor))
                .frame(width: 22)
            Text(source.name)
                .lineLimit(1)
            Spacer(minLength: 12)
            // A shortcut can become taken after it was recorded, e.g. by a system shortcut
            // turned on later.
            if let shortcut = store.shortcuts[source.id], model.recordingID != source.id,
               shortcut.problem(switcher: store.switcher) == .usedBySystem {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("macOS also uses this shortcut, so it may not work.")
            }
            ShortcutField(
                shortcut: store.shortcuts[source.id],
                isRecording: model.recordingID == source.id,
                canClear: store.shortcuts[source.id] != nil,
                clearHelp: "Clear Shortcut",
                toggle: { model.toggleRecording(source.id) },
                clear: { model.clear(source.id) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// A shortcut recorder in the style of System Settings: a field showing the shortcut,
/// faint when empty, outlined while recording, with a clear button inside.
private struct ShortcutField: View {
    let shortcut: Shortcut?
    let isRecording: Bool
    let canClear: Bool
    let clearHelp: LocalizedStringKey
    let toggle: () -> Void
    let clear: () -> Void

    private static let width: CGFloat = 130
    private static let shape = RoundedRectangle(cornerRadius: 6)

    var body: some View {
        Button(action: toggle) {
            Group {
                if isRecording {
                    Text("Type Shortcut…")
                        .foregroundStyle(Color.accentColor)
                } else if let shortcut {
                    Text(verbatim: shortcut.displayString)
                } else {
                    Text("Record Shortcut")
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, showsClear ? 22 : 8)
            .frame(width: Self.width, height: 24)
            .background(shortcut == nil && !isRecording ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary), in: Self.shape)
            .overlay {
                Self.shape.strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(shortcut == nil ? 0.35 : 0),
                                        style: StrokeStyle(lineWidth: isRecording ? 1.5 : 1, dash: shortcut == nil && !isRecording ? [3, 2] : []))
            }
            .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if showsClear {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(clearHelp)
                .padding(.trailing, 5)
            }
        }
    }

    private var showsClear: Bool { canClear && !isRecording }
}

#Preview {
    // Previews run under the app's bundle ID; keep their shortcuts out of its settings.
    let defaults = UserDefaults(suiteName: "IMESwitchPreview")!
    defaults.removePersistentDomain(forName: "IMESwitchPreview")
    let model = ShortcutsModel(store: ShortcutStore(defaults: defaults))
    model.sources = [
        InputSource(id: "com.apple.keylayout.US", name: "U.S.", isKeyboardLayout: true, label: "A"),
        InputSource(id: "com.apple.inputmethod.SCIM.ITABC", name: "Pinyin – Simplified", isKeyboardLayout: false, label: "简拼"),
        InputSource(id: "com.apple.inputmethod.TCIM.Pinyin", name: "Pinyin – Traditional", isKeyboardLayout: false, label: "繁拼"),
        InputSource(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", name: "Hiragana", isKeyboardLayout: false, label: "あ"),
    ]
    // ⌃⌥1 for U.S., to show a recorded shortcut and its clear button.
    model.store.set(Shortcut(keyCode: 18, flags: [.maskControl, .maskAlternate]), for: "com.apple.keylayout.US")
    // Hiragana skipped when cycling.
    model.store.setExcluded(true, for: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese")
    return ShortcutsView(model: model)
}

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
        VStack(alignment: .leading, spacing: 14) {
            switcherRow
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Text("Press a shortcut anywhere to switch straight to that input source.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(model.sources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 { Divider().padding(.leading, 44) }
                    row(source)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .firstTextBaseline) {
                Text(model.message ?? (model.recordingID == nil
                    ? "Click a shortcut to change it."
                    : "Type the new shortcut. Esc cancels, Delete clears."))
                    .font(.caption)
                    .foregroundStyle(model.message == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Edit Input Sources…") {
                    model.stopRecording()
                    Permissions.openInputSourceSettings()
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var switcherRow: some View {
        let id = ShortcutsModel.switcherID
        let conflicts = model.recordingID == id ? [] : Permissions.conflictingSystemShortcuts()
        return HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Switch Input Sources")
                Text("Hold and press repeatedly to cycle; add ⇧ to go back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if !conflicts.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("macOS uses this shortcut too: \(conflicts.formatted(.list(type: .and))). Turn it off in Keyboard Shortcuts.")
            }
            RecorderButton(
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
            RecorderButton(
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

private struct RecorderButton: View {
    let shortcut: Shortcut?
    let isRecording: Bool
    let canClear: Bool
    let clearHelp: LocalizedStringKey
    let toggle: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Group {
                    if isRecording {
                        Text("Type Shortcut…")
                            .foregroundStyle(Color.accentColor)
                    } else if let shortcut {
                        Text(verbatim: shortcut.displayString)
                    } else {
                        Text("Record Shortcut")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)

            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(clearHelp)
            .opacity(!canClear || isRecording ? 0 : 1)
            .disabled(!canClear || isRecording)
        }
    }
}

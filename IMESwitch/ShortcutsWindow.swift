import AppKit
import SwiftUI

/// Lists the enabled input sources, each with a recorder for a shortcut that switches
/// straight to it.
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
            window.title = String(localized: "Input Source Shortcuts")
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
            case 53: // Esc
                stopRecording()
                return
            case 51, 117: // Delete, Forward Delete
                store.set(nil, for: id)
                stopRecording()
                return
            default:
                break
            }
        }
        switch shortcut.problem {
        case .needsModifier:
            message = "Use ⌘, ⌃ or ⌥ with the key, or a function key."
            NSSound.beep()
        case .reserved:
            message = "⌘Space is already used to cycle input sources."
            NSSound.beep()
        case .usedBySystem:
            message = "macOS already uses this shortcut. Pick another, or turn it off in Keyboard Shortcuts."
            NSSound.beep()
        case nil:
            store.set(shortcut, for: id)
            stopRecording()
        }
    }

    func clear(_ id: String) {
        stopRecording()
        store.set(nil, for: id)
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
               shortcut.problem == .usedBySystem {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("macOS also uses this shortcut, so it may not work.")
            }
            RecorderButton(
                shortcut: store.shortcuts[source.id],
                isRecording: model.recordingID == source.id,
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
            .help("Clear Shortcut")
            .opacity(shortcut == nil || isRecording ? 0 : 1)
            .disabled(shortcut == nil || isRecording)
        }
    }
}

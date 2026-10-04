import AppKit
import ServiceManagement
import SwiftUI

/// Walks through the two system settings IMESwitch needs: Accessibility access, and
/// turning off the system shortcuts on the switcher's keys (⌘Space by default). Each
/// step's status updates live.
@MainActor
final class OnboardingWindow {
    private let model = OnboardingModel()
    private var window: NSWindow?

    /// Whether everything is set up, so launch can skip the window.
    static var isComplete: Bool {
        Permissions.isAccessibilityTrusted && Permissions.conflictingSystemShortcuts().isEmpty
    }

    func show() {
        model.refresh()
        model.startPolling()
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Set Up IMESwitch")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.stopPolling() }
            }
            self.window = window
        }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class OnboardingModel: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var conflicts: [String] = []
    @Published var launchAtLogin = false
    @Published var switcher = ""

    private var timer: Timer?

    var isComplete: Bool { accessibilityGranted && conflicts.isEmpty }

    func refresh() {
        accessibilityGranted = Permissions.isAccessibilityTrusted
        conflicts = Permissions.conflictingSystemShortcuts()
        switcher = ShortcutStore.savedSwitcher.displayString
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to IMESwitch")
                    .font(.title2.weight(.semibold))
                Text("Two quick steps and \(model.switcher) will switch input sources in most-recently-used order.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                StepRow(
                    number: 1,
                    done: model.accessibilityGranted,
                    title: "Allow Accessibility access",
                    detail: "IMESwitch needs it to intercept \(model.switcher) and to find the text cursor.",
                    action: "Open Settings…"
                ) {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                StepRow(
                    number: 2,
                    done: model.conflicts.isEmpty,
                    title: "Turn off the system \(model.switcher) shortcut",
                    detail: model.conflicts.isEmpty
                        ? "No system shortcut is using \(model.switcher)."
                        : "In Keyboard Shortcuts, turn off: \(model.conflicts.formatted(.list(type: .and)))",
                    action: "Open Keyboard Settings…"
                ) {
                    Permissions.openKeyboardShortcutSettings()
                }
            }

            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button(model.isComplete ? "Done" : "Later", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 480)
    }
}

private struct StepRow: View {
    let number: Int
    let done: Bool
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: LocalizedStringKey
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .animation(.easeOut(duration: 0.2), value: done)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !done {
                    Button(action, action: perform)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

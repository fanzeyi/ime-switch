import AppKit
import SwiftUI

@MainActor
final class SwitcherHUD {
    private let hosting = NSHostingView(rootView: HUDView(items: [], selected: 0))
    private lazy var panel: NSPanel = makePanel()
    private var items: [HUDView.Item] = []

    func show(items: [InputSource], selected: Int, near caret: NSRect?) {
        self.items = items.map { HUDView.Item(id: $0.id, label: $0.label) }
        // Assigning rootView updates synchronously, so fittingSize reflects the new
        // items even on the very first show.
        hosting.rootView = HUDView(items: self.items, selected: selected)
        hosting.layoutSubtreeIfNeeded()

        let wasVisible = panel.isVisible
        let size = hosting.fittingSize
        if !wasVisible {
            panel.setFrame(frame(for: size, near: caret), display: false)
            panel.orderFrontRegardless()
        } else if panel.frame.size != size {
            var frame = panel.frame
            frame.size = size
            panel.setFrame(frame, display: true)
        }
    }

    func update(selected: Int) {
        hosting.rootView = HUDView(items: items, selected: selected)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func frame(for size: NSSize, near caret: NSRect?) -> NSRect {
        let gap: CGFloat = 6
        if let caret, let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret) || $0.frame.contains(caret.origin) }) {
            let visible = screen.visibleFrame
            var origin = NSPoint(x: caret.minX - 12, y: caret.minY - gap - size.height)
            if origin.y < visible.minY {
                origin.y = caret.maxY + gap
            }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
            return NSRect(origin: origin, size: size)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        return panel
    }
}

private struct HUDView: View {
    struct Item: Identifiable {
        let id: String
        let label: String
    }

    let items: [Item]
    let selected: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isSelected = index == selected
                Text(item.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 30, minHeight: 24)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.accentColor)
                        }
                    }
            }
        }
        .padding(3)
        .background(VisualEffectBackground().clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .fixedSize()
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

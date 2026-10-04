import AppKit
import SwiftUI

/// Recreates the system input source switcher at the text caret: the highlight stays
/// pinned at the caret and the strip of sources slides under it. After a switch, macOS
/// shows its own caret indicator, so the strip just fades out.
@MainActor
final class SwitcherHUD {
    private let state = HUDState()
    private lazy var panel: NSPanel = makePanel()
    private var anchor: NSPoint?
    /// Bumped on every show or dismiss so deferred steps (fade-in, close after fade-out)
    /// from an earlier one are dropped.
    private var generation = 0

    private static let fadeOutDuration: TimeInterval = 0.12

    func showStrip(items: [InputSource], selected: Int, caret: NSRect?) {
        generation += 1
        anchor = Self.anchor(for: caret)
        withoutAnimation {
            state.items = items.map { HUDState.Item(id: $0.id, label: $0.label) }
            state.selected = selected
            state.stripVisible = false
        }
        place()
        // Lay out and draw the final geometry before fading in; otherwise the first layout
        // joins the fade's transaction and the strip morphs in from the window's corner.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let current = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == current else { return }
            withAnimation(.easeOut(duration: 0.12)) { self.state.stripVisible = true }
        }
    }

    func move(to index: Int) {
        // Measured from the system switcher: ~7 frames at 60fps, decelerating.
        withAnimation(.spring(duration: 0.15, bounce: 0)) { state.selected = index }
    }

    /// Fades the strip out.
    func dismiss() {
        generation += 1
        let current = generation
        guard panel.isVisible else { return }
        withAnimation(.easeOut(duration: Self.fadeOutDuration)) { state.stripVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOutDuration) { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }

    func hide() {
        generation += 1
        panel.orderOut(nil)
    }

    // MARK: - Layout

    /// Where the selected item is centered: like the system switcher, the highlight is
    /// centered on the caret horizontally and the strip hangs just below it. Anchoring to
    /// the caret's bottom also copes with apps that report a too-tall caret (Firefox in an
    /// empty field).
    private static func anchor(for caret: NSRect?) -> NSPoint {
        if let caret {
            return NSPoint(x: caret.minX, y: caret.minY - 1.5 - HUDLayout.stripHeight / 2)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        return NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
    }

    /// The panel is centered on the anchor and wide enough for the strip to slide either way.
    private func place() {
        guard let anchor else { return }
        let size = HUDLayout.canvasSize(itemCount: max(state.items.count, 1))
        panel.setFrame(NSRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
                              width: size.width, height: size.height), display: false)
        panel.orderFrontRegardless()
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The window is larger than what it draws; SwiftUI draws the shadows.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: HUDView(state: state))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}

private enum HUDLayout {
    // Measured from a screen recording of the system switcher.
    static let itemWidth: CGFloat = 30
    static let itemHeight: CGFloat = 23
    static let padding: CGFloat = 3
    static let margin: CGFloat = 12

    static func stripWidth(itemCount: Int) -> CGFloat {
        CGFloat(itemCount) * itemWidth + padding * 2
    }

    static var stripHeight: CGFloat { itemHeight + padding * 2 }

    static func canvasSize(itemCount: Int) -> NSSize {
        NSSize(width: stripWidth(itemCount: itemCount) * 2 + margin * 2, height: stripHeight + margin * 2)
    }

    static func itemCenter(_ index: Int) -> CGFloat {
        padding + CGFloat(index) * itemWidth + itemWidth / 2
    }
}

@MainActor
private final class HUDState: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let label: String
    }

    @Published var items: [Item] = []
    /// The item under the highlight; drives the strip's offset.
    @Published var selected = 0
    @Published var stripVisible = false
}

private struct HUDView: View {
    @ObservedObject var state: HUDState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let canvas = HUDLayout.canvasSize(itemCount: max(state.items.count, 1))
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let stripWidth = HUDLayout.stripWidth(itemCount: state.items.count)
        // The strip slides so the selected item sits at the center; the highlight never moves.
        let stripCenter = CGPoint(x: center.x - HUDLayout.itemCenter(state.selected) + stripWidth / 2, y: center.y)
        ZStack {
            if !state.items.isEmpty {
                ZStack {
                    stripBackground
                        .frame(width: stripWidth, height: HUDLayout.stripHeight)
                        .position(stripCenter)
                    highlight
                        .foregroundStyle(Color.accentColor)
                        .position(center)
                    // Labels are drawn twice, plain and white, with the white copy masked by
                    // the highlight, so whatever part of a label is under it turns white.
                    labels(highlighted: false)
                        .position(stripCenter)
                    labels(highlighted: true)
                        .position(stripCenter)
                        .mask { highlight.position(center) }
                }
                .opacity(state.stripVisible ? 1 : 0)
                .scaleEffect(state.stripVisible ? 1 : 0.96)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    /// Liquid Glass where available, like the system switcher; a HUD material before that.
    /// Reduce Transparency gets a solid background, as the system switcher does. Increase
    /// Contrast adds a visible border, which the system switcher doesn't.
    @ViewBuilder private var stripBackground: some View {
        if reduceTransparency {
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(border)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        } else if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: Capsule())
                .overlay { if contrast == .increased { border } }
        } else {
            VisualEffectBackground()
                .clipShape(Capsule())
                .overlay(border)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
    }

    /// Hairline normally; a full point in the stronger separator color with Increase Contrast.
    private var border: some View {
        Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 1 : 0.5)
    }

    private var highlight: some View {
        Capsule().frame(width: HUDLayout.itemWidth, height: HUDLayout.itemHeight)
    }

    private func labels(highlighted: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(state.items) { item in
                label(item.label, highlighted: highlighted)
            }
        }
        .padding(.horizontal, HUDLayout.padding)
    }

    private func label(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(Font(LabelStyle.font(for: text)))
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .fixedSize()
            .scaleEffect(x: LabelStyle.scaleX(for: text), y: 1)
            .frame(width: HUDLayout.itemWidth, height: HUDLayout.itemHeight)
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

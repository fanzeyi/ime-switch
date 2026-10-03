import AppKit

/// Typography of input source labels, shared by the menu bar badge and the switcher HUD.
/// Measured against the system: multi-character labels use a smaller font and are then
/// condensed horizontally to fit.
enum LabelStyle {
    static let maxWidth: CGFloat = 15.5

    static func font(for label: String) -> NSFont {
        .systemFont(ofSize: label.count > 1 ? 10.5 : 12, weight: .semibold)
    }

    static func scaleX(for label: String) -> CGFloat {
        let width = (label as NSString).size(withAttributes: [.font: font(for: label)]).width
        return min(1, maxWidth / width)
    }
}

/// Draws the system-style input source badge: a rounded rect with the label knocked out,
/// or an outlined rect for keyboard layouts. The result is a template image, so AppKit
/// tints it for the menu bar and menus.
///
/// Like the system badge, the size is fixed whatever the label; longer labels are
/// condensed horizontally instead of widening the badge.
enum BadgeImage {
    private static let size = NSSize(width: 22, height: 16)

    /// Pass `color` for contexts that don't tint template images (e.g. text attachments);
    /// dynamic colors resolve when the image is drawn.
    static func make(label: String, outlined: Bool = false, color: NSColor? = nil) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: LabelStyle.font(for: label),
            .foregroundColor: color ?? .black,
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let scaleX = LabelStyle.scaleX(for: label)

        let image = NSImage(size: size, flipped: false) { rect in
            let radius: CGFloat = 5
            if outlined {
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: radius, yRadius: radius)
                path.lineWidth = 1.5
                (color ?? .black).setStroke()
                path.stroke()
            } else {
                (color ?? .black).setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            }
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: (rect.width - textSize.width * scaleX) / 2,
                                y: (rect.height - textSize.height) / 2)
            context.scaleBy(x: scaleX, y: 1)
            (label as NSString).draw(at: .zero, withAttributes: attributes)
            context.restoreGState()
            return true
        }
        image.isTemplate = color == nil
        image.accessibilityDescription = label
        return image
    }
}

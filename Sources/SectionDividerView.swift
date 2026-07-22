import AppKit

@MainActor
final class SectionDividerView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 9)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        dividerColor.setFill()
        NSBezierPath(
            rect: NSRect(
                x: bounds.minX,
                y: floor(bounds.midY),
                width: bounds.width,
                height: 1
            )
        ).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var dividerColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.12)
    }
}

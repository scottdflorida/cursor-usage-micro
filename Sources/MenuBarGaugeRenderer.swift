import AppKit

@MainActor
enum MenuBarGaugeRenderer {
    private enum Layout {
        static let contentWidth: CGFloat = 44
        static let brandFontSize: CGFloat = 10
        static let imageHeight: CGFloat = 22
        static let trackHeight: CGFloat = 8
        static let trackBottomInset: CGFloat = 1
        static let markerWidth: CGFloat = 2
        static let outlineWidth: CGFloat = 1
        static let staleBadgeDiameter: CGFloat = 8
        static let staleBadgeGap: CGFloat = 1
        static let staleBadgeFontSize: CGFloat = 5
    }

    static let statusItemLength: CGFloat = 48

    static func image(for displayState: MenuBarDisplayState) -> NSImage {
        let brandAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Layout.brandFontSize, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let brandText = displayState.brandName as NSString
        let brandSize = brandText.size(withAttributes: brandAttributes)
        let staleBadgeWidth =
            displayState.freshness == .stale
            ? Layout.staleBadgeDiameter + Layout.staleBadgeGap
            : 0
        let availableBrandWidth = Layout.contentWidth - staleBadgeWidth
        let imageSize = NSSize(
            width: Layout.contentWidth,
            height: Layout.imageHeight
        )

        let image = NSImage(size: imageSize, flipped: false) { bounds in
            let brandRect = NSRect(
                x: bounds.minX + (availableBrandWidth - ceil(brandSize.width)) / 2,
                y: bounds.maxY - brandSize.height,
                width: ceil(brandSize.width),
                height: brandSize.height
            )
            brandText.draw(in: brandRect, withAttributes: brandAttributes)
            if displayState.freshness == .stale {
                drawStaleBadge(in: bounds, brandSlotWidth: Layout.contentWidth)
            }

            let trackRect = NSRect(
                x: bounds.minX,
                y: bounds.minY + Layout.trackBottomInset,
                width: Layout.contentWidth,
                height: Layout.trackHeight
            )
            drawGauge(displayState.gauge, in: trackRect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawGauge(_ state: MenuBarGaugeState, in trackRect: NSRect) {
        let trackPath = capsulePath(in: trackRect)
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        trackPath.fill()

        switch state {
        case .loading, .unavailable:
            drawStatus(state.statusSymbol, in: trackRect)
        case .value(let reading):
            drawReading(reading, trackPath: trackPath, trackRect: trackRect)
        }

        drawOutline(in: trackRect)
    }

    private static func capsulePath(in rect: NSRect) -> NSBezierPath {
        NSBezierPath(
            roundedRect: rect,
            xRadius: rect.height / 2,
            yRadius: rect.height / 2
        )
    }

    private static func drawOutline(in trackRect: NSRect) {
        let inset = Layout.outlineWidth / 2
        let outlinePath = capsulePath(in: trackRect.insetBy(dx: inset, dy: inset))
        outlinePath.lineWidth = Layout.outlineWidth
        NSColor.labelColor.setStroke()
        outlinePath.stroke()
    }

    private static func drawReading(
        _ reading: MenuBarGaugeReading,
        trackPath: NSBezierPath,
        trackRect: NSRect
    ) {
        let usageFraction = reading.usageRemainingFraction.clamped(to: 0...1)
        let timeFraction = reading.timeRemainingFraction.clamped(to: 0...1)

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        reading.pace.color.setFill()
        NSBezierPath(
            rect: NSRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: trackRect.width * usageFraction,
                height: trackRect.height
            )
        ).fill()
        NSGraphicsContext.restoreGraphicsState()

        let rawMarkerX = trackRect.minX + trackRect.width * timeFraction
        let markerX = max(
            trackRect.minX,
            min(trackRect.maxX - Layout.markerWidth, rawMarkerX - Layout.markerWidth / 2)
        )
        let verticalInset = Layout.outlineWidth / 2
        let markerPath = NSBezierPath(
            roundedRect: NSRect(
                x: markerX,
                y: trackRect.minY + verticalInset,
                width: Layout.markerWidth,
                height: trackRect.height - Layout.outlineWidth
            ),
            xRadius: Layout.markerWidth / 2,
            yRadius: Layout.markerWidth / 2
        )
        NSColor.controlBackgroundColor.withAlphaComponent(0.98).setFill()
        markerPath.fill()
    }

    private static func drawStatus(_ symbol: String?, in trackRect: NSRect) {
        guard let symbol else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8),
        ]
        let text = symbol as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: trackRect.midX - size.width / 2,
                y: trackRect.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }

    private static func drawStaleBadge(in bounds: NSRect, brandSlotWidth: CGFloat) {
        let badgeRect = NSRect(
            x: bounds.minX + brandSlotWidth - Layout.staleBadgeDiameter,
            y: bounds.maxY - Layout.staleBadgeDiameter - 1,
            width: Layout.staleBadgeDiameter,
            height: Layout.staleBadgeDiameter
        )
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Layout.staleBadgeFontSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let text = "S" as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: badgeRect.midX - size.width / 2,
                y: badgeRect.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }
}

extension UsagePace {
    fileprivate var color: NSColor {
        switch self {
        case .critical:
            .systemRed
        case .onPace:
            .systemGreen
        case .behind:
            .systemOrange
        }
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

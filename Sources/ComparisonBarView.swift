import AppKit

@MainActor
final class ComparisonBarView: NSView {
    private enum Layout {
        static let rowHeight: CGFloat = 17
        static let trackHeight: CGFloat = 10
        static let labelGap: CGFloat = 2.5
        static let markerWidth: CGFloat = 3
    }

    private enum NamePlacement {
        case beforeValue
        case afterValue

        func updated(for fraction: Double) -> Self {
            switch (self, fraction) {
            case (.afterValue, 0.54...): .beforeValue
            case (.beforeValue, ...0.46): .afterValue
            default: self
            }
        }
    }

    private let timeName: NSTextField
    private let timeValue = NSTextField(labelWithString: "—")
    private let usageName: NSTextField
    private let usageValue = NSTextField(labelWithString: "—")

    private var timeFraction = 0.0
    private var usageFraction = 0.0
    private var usageColor = NSColor.systemGray
    private var trackRect = NSRect.zero
    private var showsReading = false
    private var timeNamePlacement = NamePlacement.afterValue
    private var usageNamePlacement = NamePlacement.afterValue

    init(timeLabel: String, usageLabel: String, accessibilityLabel: String) {
        timeName = NSTextField(labelWithString: timeLabel)
        usageName = NSTextField(labelWithString: usageLabel)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        timeName.font = .systemFont(ofSize: 12, weight: .medium)
        usageName.font = .systemFont(ofSize: 12, weight: .bold)
        for label in [timeName, usageName] {
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }

        for label in [timeValue, usageValue] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            label.alignment = .center
            addSubview(label)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityHelp("The colored bar shows usage remaining; the marker shows time remaining.")
        for label in [timeName, timeValue, usageName, usageValue] {
            label.setAccessibilityElement(false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 62)
    }

    override func layout() {
        super.layout()

        trackRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - Layout.trackHeight / 2,
            width: bounds.width,
            height: Layout.trackHeight
        )

        usageNamePlacement = layoutRow(
            name: usageName,
            value: usageValue,
            fraction: usageFraction,
            namePlacement: usageNamePlacement,
            y: bounds.maxY - Layout.rowHeight
        )
        timeNamePlacement = layoutRow(
            name: timeName,
            value: timeValue,
            fraction: timeFraction,
            namePlacement: timeNamePlacement,
            y: bounds.minY
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard trackRect.width > 0 else { return }

        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.height / 2,
            yRadius: trackRect.height / 2
        )
        trackColor.setFill()
        trackPath.fill()
        guard showsReading else { return }

        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        usageColor.setFill()
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

        NSColor.controlBackgroundColor.withAlphaComponent(0.98).setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: markerX,
                y: trackRect.minY - 2,
                width: Layout.markerWidth,
                height: trackRect.height + 4
            ),
            xRadius: 1.5,
            yRadius: 1.5
        ).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func update(reading: UsageReading, color: NSColor) {
        showsReading = true
        timeFraction = reading.timeRemainingFraction.clamped(to: 0...1)
        usageFraction = reading.usageRemainingFraction.clamped(to: 0...1)
        usageColor = color
        timeValue.stringValue = "\(reading.timeRemainingPercent)%"
        usageValue.stringValue = "\(reading.usageRemainingPercent)%"
        setAccessibilityValue(
            "Usage remaining \(reading.usageRemainingPercent) percent; "
                + "time remaining \(reading.timeRemainingPercent) percent"
        )
        needsLayout = true
        needsDisplay = true
    }

    func showUnavailable() {
        showsReading = false
        timeFraction = 0
        usageFraction = 0
        usageColor = .systemGray
        timeValue.stringValue = "—"
        usageValue.stringValue = "—"
        setAccessibilityValue("Usage unavailable")
        needsLayout = true
        needsDisplay = true
    }

    private func layoutRow(
        name: NSTextField,
        value: NSTextField,
        fraction: Double,
        namePlacement: NamePlacement,
        y: CGFloat
    ) -> NamePlacement {
        name.sizeToFit()
        value.sizeToFit()

        let valueWidth = value.frame.width
        let markerCenter = bounds.minX + bounds.width * fraction
        let preferredValueX = markerCenter - valueWidth / 2
        let nameWidth = name.frame.width
        let labelAndValueWidth = nameWidth + Layout.labelGap + valueWidth
        guard bounds.width >= labelAndValueWidth else { return namePlacement }

        let resolvedPlacement = namePlacement.updated(for: fraction)

        let valueX: CGFloat
        let nameX: CGFloat
        if resolvedPlacement == .beforeValue {
            let minimumValueX = bounds.minX + nameWidth + Layout.labelGap
            let maximumValueX = bounds.maxX - valueWidth
            valueX = preferredValueX.clamped(to: minimumValueX...maximumValueX)
            nameX = valueX - Layout.labelGap - nameWidth
            name.alignment = .right
        } else {
            let maximumValueX = bounds.maxX - labelAndValueWidth
            valueX = preferredValueX.clamped(to: bounds.minX...maximumValueX)
            nameX = valueX + valueWidth + Layout.labelGap
            name.alignment = .left
        }

        value.frame = NSRect(x: valueX, y: y, width: valueWidth, height: Layout.rowHeight)
        name.frame = NSRect(x: nameX, y: y, width: nameWidth, height: Layout.rowHeight)
        return resolvedPlacement
    }

    private var trackColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.24)
            : NSColor.black.withAlphaComponent(0.14)
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

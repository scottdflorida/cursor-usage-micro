import AppKit
import Foundation

@MainActor
final class UsageViewController: NSViewController {
    var onRefresh: (() -> Void)?
    var onContentSizeChange: ((NSSize) -> Void)?

    private let cursorModelsBar = ComparisonBarView(
        timeLabel: "Cycle remaining",
        usageLabel: "Cursor models remaining",
        accessibilityLabel: "Cursor first-party models pool"
    )
    private let apiBar = ComparisonBarView(
        timeLabel: "Cycle remaining",
        usageLabel: "API usage remaining",
        accessibilityLabel: "Cursor API models pool"
    )
    private let contentStack = NSStackView()
    private let sectionDivider = SectionDividerView()
    private let errorRow = NSView()
    private let errorLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let resetLabel = NSTextField(labelWithString: "Resets: —")
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private lazy var headerView = makeHeader()
    private lazy var footerView = makeFooter()

    private let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMdjm")
        return formatter
    }()

    private var report: UsageReport?
    private var rootHeightConstraint: NSLayoutConstraint?

    override func loadView() {
        let contentSize = AppConfiguration.compactContentSize
        let root = NSView(frame: NSRect(origin: .zero, size: contentSize))
        root.translatesAutoresizingMaskIntoConstraints = false

        resetLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        resetLabel.textColor = .secondaryLabelColor
        resetLabel.alignment = .left
        configureButton(refreshButton, action: #selector(refreshPressed))
        configureButton(quitButton, action: #selector(quitPressed))
        configureErrorRow()

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 7
        replaceArrangedSubviews(
            in: contentStack,
            with: [headerView, cursorModelsBar, footerView]
        )
        contentStack.setCustomSpacing(3, after: cursorModelsBar)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        let rootHeightConstraint = root.heightAnchor.constraint(equalToConstant: contentSize.height)
        self.rootHeightConstraint = rootHeightConstraint
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: contentSize.width),
            rootHeightConstraint,
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -3),
        ])

        preferredContentSize = contentSize
        view = root
    }

    func showLoading() {
        _ = view
        refreshButton.isEnabled = false
        setStatus("Updating…")
    }

    func show(
        report: UsageReport,
        at date: Date = Date(),
        status: UsagePresentationStatus = .live
    ) {
        _ = view
        self.report = report
        showUsagePresentation(
            cursorModelsAvailable: report.cursorModels != nil,
            apiAvailable: report.api != nil
        )
        refreshButton.isEnabled = true
        setStatus(status.label, diagnostic: status.diagnostic)
        updateClock(at: date)
    }

    func show(errorMessage: String) {
        _ = view
        report = nil
        showErrorPresentation()
        refreshButton.isEnabled = true
        cursorModelsBar.showUnavailable()
        apiBar.showUnavailable()
        resetLabel.stringValue = ""

        let diagnostic = DiagnosticText.sanitized(errorMessage)
        errorLabel.stringValue = diagnostic
        errorLabel.toolTip = diagnostic
        errorLabel.setAccessibilityValue(diagnostic)
        setStatus("Unavailable", diagnostic: diagnostic)
    }

    func updateClock(at date: Date = Date()) {
        guard let report else { return }

        if let cursorModels = report.cursorModels {
            let reading = cursorModels.reading(at: date)
            cursorModelsBar.update(reading: reading, color: reading.pace.color)
        } else {
            cursorModelsBar.showUnavailable()
        }

        if let api = report.api {
            let reading = api.reading(at: date)
            apiBar.update(reading: reading, color: reading.pace.color)
        } else {
            apiBar.showUnavailable()
        }

        if let resetDate = report.cursorModels?.resetsAt ?? report.api?.resetsAt {
            resetLabel.stringValue = "Resets: \(resetFormatter.string(from: resetDate))"
        } else {
            resetLabel.stringValue = ""
        }
    }

    private func makeHeader() -> NSView {
        let title = NSTextField(labelWithString: AppConfiguration.popoverTitle)
        title.font = .systemFont(ofSize: 12, weight: .bold)
        title.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        statusLabel.setAccessibilityLabel("Usage status")

        let header = NSView()
        for view in [header, title, statusLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        header.addSubview(title)
        header.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 16),
            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    private func makeFooter() -> NSStackView {
        let footer = NSStackView(
            views: [resetLabel, NSView(), refreshButton, quitButton]
        )
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        return footer
    }

    private func configureErrorRow() {
        errorRow.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.setAccessibilityLabel("Usage error")
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorRow.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            errorRow.heightAnchor.constraint(equalToConstant: 14),
            errorLabel.leadingAnchor.constraint(equalTo: errorRow.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: errorRow.trailingAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorRow.centerYAnchor),
        ])
    }

    private func configureButton(_ button: NSButton, action: Selector) {
        button.bezelStyle = .inline
        button.controlSize = .small
        button.target = self
        button.action = action
    }

    private func showUsagePresentation(cursorModelsAvailable: Bool, apiAvailable: Bool) {
        if cursorModelsAvailable && apiAvailable {
            replaceArrangedSubviews(
                in: contentStack,
                with: [headerView, cursorModelsBar, sectionDivider, apiBar, footerView]
            )
            contentStack.setCustomSpacing(7, after: cursorModelsBar)
            contentStack.setCustomSpacing(7, after: sectionDivider)
            contentStack.setCustomSpacing(3, after: apiBar)
        } else if cursorModelsAvailable {
            replaceArrangedSubviews(
                in: contentStack,
                with: [headerView, cursorModelsBar, footerView]
            )
            contentStack.setCustomSpacing(3, after: cursorModelsBar)
        } else {
            replaceArrangedSubviews(
                in: contentStack,
                with: [headerView, apiBar, footerView]
            )
            contentStack.setCustomSpacing(3, after: apiBar)
        }

        let contentSize = AppConfiguration.contentSize(
            cursorModelsAvailable: cursorModelsAvailable,
            apiAvailable: apiAvailable
        )
        setContentSize(contentSize)
    }

    private func showErrorPresentation() {
        replaceArrangedSubviews(
            in: contentStack,
            with: [headerView, errorRow, footerView]
        )
        contentStack.setCustomSpacing(3, after: errorRow)
        setContentSize(AppConfiguration.errorContentSize)
    }

    private func replaceArrangedSubviews(
        in stack: NSStackView,
        with views: [NSView]
    ) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            stack.addArrangedSubview(view)
        }
    }

    private func setContentSize(_ contentSize: NSSize) {
        rootHeightConstraint?.constant = contentSize.height
        guard preferredContentSize != contentSize else { return }

        preferredContentSize = contentSize
        onContentSizeChange?(contentSize)
    }

    private func setStatus(_ value: String, diagnostic: String? = nil) {
        statusLabel.stringValue = value
        statusLabel.toolTip = diagnostic
        statusLabel.setAccessibilityValue(
            diagnostic.map { "\(value). \($0)" } ?? value
        )
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func quitPressed() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit \(AppConfiguration.name)?"
        alert.informativeText =
            "The menu-bar indicator will disappear until you open "
            + "\(AppConfiguration.name) again."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }
}

enum UsagePresentationStatus: Equatable {
    case live
    case stale(String)

    var label: String {
        switch self {
        case .live: "Live"
        case .stale: "Stale"
        }
    }

    var diagnostic: String? {
        switch self {
        case .live: nil
        case .stale(let diagnostic): diagnostic
        }
    }
}

extension UsagePace {
    fileprivate var color: NSColor {
        switch self {
        case .critical: .systemRed
        case .onPace: .systemGreen
        case .behind: .systemOrange
        }
    }
}

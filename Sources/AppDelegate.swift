import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let client: any UsageFetching
    private let viewController = UsageViewController()
    private let popover = NSPopover()

    private var menuBarDisplayState = MenuBarDisplayState.loading
    private var statusItem: NSStatusItem?
    private var report: UsageReport?
    private var staleDiagnostic: String?
    private var refreshTask: Task<Void, Never>?
    private var usageTimer: Timer?
    private var clockTimer: Timer?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    init(client: any UsageFetching = CursorUsageClient()) {
        self.client = client
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusItem()
        scheduleTimers()
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        usageTimer?.invalidate()
        clockTimer?.invalidate()
        stopLocalClickMonitor()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = AppConfiguration.compactContentSize
        popover.contentViewController = viewController
        viewController.onRefresh = { [weak self] in self?.refresh() }
        viewController.onContentSizeChange = { [weak self] size in
            self?.popover.contentSize = size
        }
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: MenuBarGaugeRenderer.statusItemLength
        )
        self.statusItem = statusItem
        // Keep visibility owned by this process. An autosave name lets macOS persist an
        // externally hidden status item across launches, even while the app is healthy.
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }

        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "Cursor and Grok usage"
        button.setAccessibilityLabel("Cursor and Grok usage")
        button.setAccessibilityValue("Usage unavailable")
        button.setAccessibilityHelp("Opens available Cursor usage-pool details.")
        renderStatusItem()
    }

    private func scheduleTimers() {
        let usageTimer = Timer(
            timeInterval: AppConfiguration.automaticRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        usageTimer.tolerance = AppConfiguration.automaticRefreshInterval / 10
        RunLoop.main.add(usageTimer, forMode: .common)
        self.usageTimer = usageTimer

        let clockTimer = Timer(
            timeInterval: AppConfiguration.clockRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        clockTimer.tolerance = 5
        RunLoop.main.add(clockTimer, forMode: .common)
        self.clockTimer = clockTimer
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startLocalClickMonitor()
            refresh()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopLocalClickMonitor()
    }

    private func refresh() {
        guard refreshTask == nil else { return }

        viewController.showLoading()
        if report == nil {
            menuBarDisplayState = .loading
            renderStatusItem()
            statusItem?.button?.toolTip = "Checking Cursor usage"
            statusItem?.button?.setAccessibilityValue("Checking usage")
        }
        refreshTask = Task { [weak self, client] in
            do {
                let report = try await client.fetch()
                guard let self else { return }
                self.report = report
                self.staleDiagnostic = nil
                self.viewController.show(report: report)
                self.updateStatusItem(with: report)
            } catch is CancellationError {
                // Application shutdown owns cancellation; no error state should flash on exit.
            } catch {
                guard let self else { return }
                let diagnostic = DiagnosticText.sanitized(error.localizedDescription)
                if let report = self.report,
                    RefreshFailurePolicy.preservesLastReport(
                        for: error,
                        report: report
                    )
                {
                    self.staleDiagnostic = diagnostic
                    self.viewController.show(
                        report: report,
                        status: .stale(diagnostic)
                    )
                    self.updateStatusItem(with: report, diagnostic: diagnostic)
                } else {
                    self.showUnavailable(diagnostic: diagnostic)
                }
            }
            self?.refreshTask = nil
        }
    }

    private func tick(at date: Date = Date()) {
        if let report, let staleDiagnostic,
            !report.hasUnexpiredUsage(at: date)
        {
            showUnavailable(diagnostic: staleDiagnostic)
            return
        }

        viewController.updateClock(at: date)
        if let report {
            updateStatusItem(with: report, at: date, diagnostic: staleDiagnostic)
        }
    }

    private func updateStatusItem(
        with report: UsageReport,
        at date: Date = Date(),
        diagnostic: String? = nil
    ) {
        menuBarDisplayState = .live(
            report: report,
            at: date,
            freshness: diagnostic == nil ? .current : .stale
        )
        renderStatusItem()

        var toolTipLines: [String] = []
        var accessibilityDetails: [String] = []
        if let cursorModels = report.cursorModels {
            let reading = cursorModels.reading(at: date)
            toolTipLines.append(
                "Cursor models · Usage left \(reading.usageRemainingPercent)% · "
                    + "Cycle left \(reading.timeRemainingPercent)%"
            )
            accessibilityDetails.append(
                "Cursor model usage remaining \(reading.usageRemainingPercent) percent, "
                    + "cycle remaining \(reading.timeRemainingPercent) percent"
            )
        }

        if let api = report.api {
            let reading = api.reading(at: date)
            toolTipLines.append(
                "API · Usage left \(reading.usageRemainingPercent)% · "
                    + "Cycle left \(reading.timeRemainingPercent)%"
            )
            accessibilityDetails.append(
                "API usage remaining \(reading.usageRemainingPercent) percent, "
                    + "cycle remaining \(reading.timeRemainingPercent) percent"
            )
        }

        if let diagnostic {
            toolTipLines.insert("Last update shown · \(diagnostic)", at: 0)
        }

        statusItem?.button?.toolTip = toolTipLines.joined(separator: "\n")
        let accessibilityPrefix = diagnostic.map { "Last update shown. \($0). " } ?? ""
        if case .value(let reading) = menuBarDisplayState.gauge,
            let limitName = menuBarDisplayState.limitName
        {
            statusItem?.button?.setAccessibilityValue(
                accessibilityPrefix
                    + "\(limitName) usage remaining \(reading.usageRemainingPercent) percent, "
                    + "cycle remaining \(Int((reading.timeRemainingFraction * 100).rounded())) percent"
            )
        } else {
            statusItem?.button?.setAccessibilityValue(
                accessibilityPrefix + accessibilityDetails.joined(separator: "; ")
            )
        }
    }

    private func renderStatusItem() {
        guard let button = statusItem?.button else { return }

        button.image = MenuBarGaugeRenderer.image(for: menuBarDisplayState)
        statusItem?.isVisible = true
    }

    private func showUnavailable(diagnostic: String) {
        report = nil
        staleDiagnostic = nil
        viewController.show(errorMessage: diagnostic)
        menuBarDisplayState = .unavailable
        renderStatusItem()
        statusItem?.button?.toolTip = diagnostic
        statusItem?.button?.setAccessibilityValue("Usage unavailable")
    }

    private func startLocalClickMonitor() {
        guard localClickMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem?.button?.window
            if event.window !== popoverWindow && event.window !== statusWindow {
                self.popover.performClose(nil)
            }
            return event
        }
        // Transient behavior alone misses clicks in other apps when this accessory
        // app was never active; global mouse-down monitors need no permissions.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popover.performClose(nil)
            }
        }
    }

    private func stopLocalClickMonitor() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }
}

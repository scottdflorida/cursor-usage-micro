import AppKit
import Foundation

func usageViewControllerTests() -> [TestCase] {
    let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
    let resetsAt = startsAt.addingTimeInterval(2_678_400)

    func snapshot(usedPercent: Double) -> UsageSnapshot {
        guard
            let snapshot = UsageSnapshot(
                usedPercent: usedPercent,
                startsAt: startsAt,
                resetsAt: resetsAt
            )
        else {
            preconditionFailure("Invalid UsageSnapshot test fixture")
        }
        return snapshot
    }

    func report(cursorModels: UsageSnapshot?, api: UsageSnapshot?) -> UsageReport {
        guard let report = UsageReport(cursorModels: cursorModels, api: api) else {
            preconditionFailure("Invalid UsageReport test fixture")
        }
        return report
    }

    @MainActor
    func visibleText(in view: NSView) -> [String] {
        let ownValue = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return ownValue
            + view.subviews
            .filter { !$0.isHidden }
            .flatMap(visibleText(in:))
    }

    return [
        TestCase(name: "popover expands for both Cursor usage pools and collapses for one") {
            try await MainActor.run {
                _ = NSApplication.shared
                let viewController = UsageViewController()

                viewController.show(
                    report: report(
                        cursorModels: snapshot(usedPercent: 5),
                        api: snapshot(usedPercent: 10)
                    ),
                    at: startsAt
                )
                try expectEqual(viewController.preferredContentSize, AppConfiguration.expandedContentSize)
                let expandedText = visibleText(in: viewController.view)
                try expect(expandedText.contains("CURSOR / GROK USAGE"), "expected merged product title")
                try expect(expandedText.contains("Cursor models remaining"), "expected first-party pool")
                try expect(expandedText.contains("API usage remaining"), "expected API pool")

                viewController.show(
                    report: report(cursorModels: snapshot(usedPercent: 5), api: nil),
                    at: startsAt
                )
                try expectEqual(viewController.preferredContentSize, AppConfiguration.compactContentSize)
                try expect(
                    !visibleText(in: viewController.view).contains("API usage remaining"),
                    "expected absent API pool to be hidden"
                )

                viewController.show(
                    report: report(cursorModels: nil, api: snapshot(usedPercent: 10)),
                    at: startsAt
                )
                try expectEqual(viewController.preferredContentSize, AppConfiguration.compactContentSize)
                let apiOnlyText = visibleText(in: viewController.view)
                try expect(apiOnlyText.contains("API usage remaining"), "expected API pool")
                try expect(
                    !apiOnlyText.contains("Cursor models remaining"),
                    "expected absent first-party pool to be hidden"
                )

                viewController.show(
                    report: report(cursorModels: snapshot(usedPercent: 5), api: nil),
                    at: startsAt,
                    status: .stale("Cursor did not respond")
                )
                try expect(
                    visibleText(in: viewController.view).contains("Stale"),
                    "expected stale data to be labeled"
                )
            }
        },
        TestCase(name: "popover error presentation is compact") {
            try await MainActor.run {
                _ = NSApplication.shared
                let viewController = UsageViewController()
                viewController.show(errorMessage: "Cursor login expired")
                try expectEqual(viewController.preferredContentSize, AppConfiguration.errorContentSize)
            }
        },
    ]
}

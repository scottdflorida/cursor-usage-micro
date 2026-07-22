import AppKit
import Foundation

func menuBarTests() -> [TestCase] {
    let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
    let halfway = startsAt.addingTimeInterval(50)
    let resetsAt = startsAt.addingTimeInterval(100)

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

    return [
        TestCase(name: "menu bar follows the Cursor models pool used by Grok") {
            let state = MenuBarDisplayState.live(
                report: report(
                    cursorModels: snapshot(usedPercent: 20),
                    api: snapshot(usedPercent: 75)
                ),
                at: halfway
            )
            try expectEqual(state.brandName, "Cursor")
            try expectEqual(state.limitName, "Cursor models")
            guard case .value(let reading) = state.gauge else {
                throw TestFailure(description: "expected a live gauge")
            }
            try expectEqual(reading.usageRemainingPercent, 80)
        },
        TestCase(name: "menu bar falls back to API when split-pool data omits Cursor models") {
            let state = MenuBarDisplayState.live(
                report: report(cursorModels: nil, api: snapshot(usedPercent: 25)),
                at: halfway
            )
            try expectEqual(state.limitName, "API")
        },
        TestCase(name: "stale menu-bar usage has a distinct visible badge") {
            let usageReport = report(
                cursorModels: snapshot(usedPercent: 20),
                api: nil
            )
            let current = MenuBarDisplayState.live(
                report: usageReport,
                at: halfway
            )
            let stale = MenuBarDisplayState.live(
                report: usageReport,
                at: halfway,
                freshness: .stale
            )
            try expectEqual(current.freshness, .current)
            try expectEqual(stale.freshness, .stale)

            try await MainActor.run {
                let currentImage = MenuBarGaugeRenderer.image(for: current)
                let staleImage = MenuBarGaugeRenderer.image(for: stale)
                try expect(
                    currentImage.tiffRepresentation != staleImage.tiffRepresentation,
                    "expected stale rendering to differ visibly"
                )
            }
        },
    ]
}

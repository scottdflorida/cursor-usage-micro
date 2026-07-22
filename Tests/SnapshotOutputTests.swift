import Foundation

func snapshotOutputTests() -> [TestCase] {
    let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
    let resetsAt = startsAt.addingTimeInterval(100)
    let halfway = startsAt.addingTimeInterval(50)

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
        TestCase(name: "snapshot output is stable and ordered for both pools") {
            let lines = SnapshotOutput.lines(
                for: report(
                    cursorModels: snapshot(usedPercent: 25),
                    api: snapshot(usedPercent: 75)
                ),
                at: halfway
            )
            try expectEqual(
                lines,
                [
                    "cursor_models_time_remaining=50",
                    "cursor_models_usage_remaining=75",
                    "cursor_models_resets_at=1700000100",
                    "api_time_remaining=50",
                    "api_usage_remaining=25",
                    "api_resets_at=1700000100",
                ]
            )
        },
        TestCase(name: "snapshot output omits an unavailable pool") {
            let lines = SnapshotOutput.lines(
                for: report(cursorModels: nil, api: snapshot(usedPercent: 25)),
                at: halfway
            )
            try expectEqual(lines.count, 3)
            try expect(lines.allSatisfy { $0.hasPrefix("api_") }, "expected only API fields")
        },
    ]
}

import Foundation

func refreshFailurePolicyTests() -> [TestCase] {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func report(resetsAt: Date) -> UsageReport {
        guard
            let snapshot = UsageSnapshot(
                usedPercent: 25,
                startsAt: now.addingTimeInterval(-100),
                resetsAt: resetsAt
            ),
            let report = UsageReport(cursorModels: snapshot, api: nil)
        else {
            preconditionFailure("Invalid refresh-policy test fixture")
        }
        return report
    }

    return [
        TestCase(name: "transient and schema failures preserve an explicitly stale report") {
            try expect(
                RefreshFailurePolicy.preservesLastReport(for: CursorUsageClientError.timedOut),
                "expected timeout preservation"
            )
            try expect(
                RefreshFailurePolicy.preservesLastReport(for: CursorUsageClientError.invalidResponse),
                "expected schema-change preservation"
            )
            try expect(
                RefreshFailurePolicy.preservesLastReport(
                    for: CursorCredentialStoreError.couldNotReadDatabase
                ),
                "expected transient database-read preservation"
            )
        },
        TestCase(name: "logout and disabled usage invalidate account data") {
            try expect(
                !RefreshFailurePolicy.preservesLastReport(for: CursorUsageClientError.loginExpired),
                "expected expired login invalidation"
            )
            try expect(
                !RefreshFailurePolicy.preservesLastReport(for: CursorUsageClientError.usageUnavailable),
                "expected disabled usage invalidation"
            )
            try expect(
                !RefreshFailurePolicy.preservesLastReport(for: CursorCredentialStoreError.notSignedIn),
                "expected local logout invalidation"
            )
        },
        TestCase(name: "stale reports expire with their last usage window") {
            try expect(
                RefreshFailurePolicy.preservesLastReport(
                    for: CursorUsageClientError.invalidResponse,
                    report: report(resetsAt: now.addingTimeInterval(1)),
                    at: now
                ),
                "expected an active stale window to remain visible"
            )
            try expect(
                !RefreshFailurePolicy.preservesLastReport(
                    for: CursorUsageClientError.invalidResponse,
                    report: report(resetsAt: now),
                    at: now
                ),
                "expected an expired stale window to clear"
            )
        },
    ]
}

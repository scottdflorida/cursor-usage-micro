import Foundation

func usageModelTests() -> [TestCase] {
    let startsAt = Date(timeIntervalSince1970: 1_700_000_000)
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

    return [
        TestCase(name: "sub-percent usage matches Cursor's one-percent display floor") {
            let value = snapshot(usedPercent: 0.08)
            try expectEqual(value.usageRemainingPercent, 99)
            try expect(abs(value.usageRemainingFraction - 0.9992) < 0.000_001, "unexpected fraction")
        },
        TestCase(name: "usage percentage boundaries are calculated") {
            try expectEqual(snapshot(usedPercent: 0).usageRemainingPercent, 100)
            try expectEqual(snapshot(usedPercent: 35).usageRemainingPercent, 65)
            try expectEqual(snapshot(usedPercent: 100).usageRemainingPercent, 0)
        },
        TestCase(name: "snapshot rejects malformed provider values") {
            try expectEqual(UsageSnapshot(usedPercent: -1, startsAt: startsAt, resetsAt: resetsAt), nil)
            try expectEqual(UsageSnapshot(usedPercent: .infinity, startsAt: startsAt, resetsAt: resetsAt), nil)
            try expectEqual(UsageSnapshot(usedPercent: 50, startsAt: startsAt, resetsAt: startsAt), nil)
        },
        TestCase(name: "overage is valid usage with no remaining capacity") {
            let value = snapshot(usedPercent: 125)
            try expectEqual(value.usageRemainingPercent, 0)
            try expectEqual(value.usageRemainingFraction, 0)
            try expectEqual(value.reading(at: startsAt).pace, .critical)
            try expectEqual(snapshot(usedPercent: .greatestFiniteMagnitude).usageRemainingPercent, 0)
        },
        TestCase(name: "cycle time is clamped at both boundaries") {
            let value = snapshot(usedPercent: 25)
            try expectEqual(value.timeRemainingFraction(at: startsAt.addingTimeInterval(-1)), 1)
            try expectEqual(value.timeRemainingFraction(at: resetsAt.addingTimeInterval(1)), 0)
        },
        TestCase(name: "usage pacing compares the exact capacity and cycle fractions") {
            let value = snapshot(usedPercent: 60)
            try expectEqual(
                value.reading(at: startsAt.addingTimeInterval(50)).pace,
                .behind
            )
            try expectEqual(
                snapshot(usedPercent: 20).reading(at: startsAt.addingTimeInterval(50)).pace,
                .onPace
            )
        },
        TestCase(name: "critical capacity takes priority over pacing") {
            try expectEqual(
                snapshot(usedPercent: 86).reading(at: resetsAt.addingTimeInterval(-1)).pace,
                .critical
            )
        },
    ]
}

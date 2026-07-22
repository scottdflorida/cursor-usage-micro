import Foundation

struct UsageReport: Equatable, Sendable {
    let cursorModels: UsageSnapshot?
    let api: UsageSnapshot?

    init?(cursorModels: UsageSnapshot?, api: UsageSnapshot?) {
        guard cursorModels != nil || api != nil else { return nil }
        self.cursorModels = cursorModels
        self.api = api
    }

    func hasUnexpiredUsage(at date: Date = Date()) -> Bool {
        [cursorModels, api].compactMap { $0 }.contains { $0.resetsAt > date }
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let usedPercent: Double
    let startsAt: Date
    let resetsAt: Date

    init?(usedPercent: Double, startsAt: Date, resetsAt: Date) {
        let windowDuration = resetsAt.timeIntervalSince(startsAt)
        guard
            usedPercent.isFinite,
            usedPercent >= 0,
            startsAt.timeIntervalSinceReferenceDate.isFinite,
            resetsAt.timeIntervalSinceReferenceDate.isFinite,
            windowDuration.isFinite,
            windowDuration > 0
        else {
            return nil
        }

        self.usedPercent = usedPercent
        self.startsAt = startsAt
        self.resetsAt = resetsAt
    }

    var usageRemainingFraction: Double {
        (1 - usedPercent / 100).clamped(to: 0...1)
    }

    var usageRemainingPercent: Int {
        100 - displayedUsedPercent
    }

    func timeRemainingFraction(at date: Date = Date()) -> Double {
        let windowDuration = resetsAt.timeIntervalSince(startsAt)
        guard windowDuration.isFinite, windowDuration > 0 else { return 0 }

        let timeRemaining = resetsAt.timeIntervalSince(date)
        guard timeRemaining.isFinite else {
            return timeRemaining == .infinity ? 1 : 0
        }

        return (timeRemaining / windowDuration)
            .clamped(to: 0...1)
    }

    func reading(at date: Date = Date()) -> UsageReading {
        let timeFraction = timeRemainingFraction(at: date)
        let timePercent = Int((timeFraction * 100).rounded())

        let pace: UsagePace
        if usageRemainingFraction < 0.15 {
            pace = .critical
        } else if usageRemainingFraction >= timeFraction {
            pace = .onPace
        } else {
            pace = .behind
        }

        return UsageReading(
            timeRemainingFraction: timeFraction,
            timeRemainingPercent: timePercent,
            usageRemainingFraction: usageRemainingFraction,
            usageRemainingPercent: usageRemainingPercent,
            pace: pace
        )
    }

    private var displayedUsedPercent: Int {
        if usedPercent > 0, usedPercent < 1 {
            return 1
        }
        guard usedPercent < 100 else { return 100 }
        return Int(usedPercent.rounded())
    }
}

struct UsageReading: Equatable, Sendable {
    let timeRemainingFraction: Double
    let timeRemainingPercent: Int
    let usageRemainingFraction: Double
    let usageRemainingPercent: Int
    let pace: UsagePace
}

enum UsagePace: Equatable, Sendable {
    case critical
    case onPace
    case behind
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

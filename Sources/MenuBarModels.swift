import Foundation

struct MenuBarGaugeReading: Equatable, Sendable {
    let usageRemainingFraction: Double
    let timeRemainingFraction: Double
    let usageRemainingPercent: Int
    let pace: UsagePace
}

enum MenuBarGaugeState: Equatable, Sendable {
    case loading
    case value(MenuBarGaugeReading)
    case unavailable

    var statusSymbol: String? {
        switch self {
        case .loading:
            "…"
        case .value:
            nil
        case .unavailable:
            "!"
        }
    }
}

enum MenuBarFreshness: Equatable, Sendable {
    case current
    case stale
}

struct MenuBarDisplayState: Equatable, Sendable {
    let brandName: String
    let gauge: MenuBarGaugeState
    let limitName: String?
    let freshness: MenuBarFreshness

    static let loading = MenuBarDisplayState(
        brandName: "Cursor",
        gauge: .loading,
        limitName: nil,
        freshness: .current
    )

    static let unavailable = MenuBarDisplayState(
        brandName: "Cursor",
        gauge: .unavailable,
        limitName: nil,
        freshness: .current
    )

    static func live(
        report: UsageReport,
        at date: Date = Date(),
        freshness: MenuBarFreshness = .current
    ) -> MenuBarDisplayState {
        let usesCursorModels = report.cursorModels != nil
        guard let snapshot = report.cursorModels ?? report.api else {
            return unavailable
        }

        let reading = snapshot.reading(at: date)
        return MenuBarDisplayState(
            brandName: "Cursor",
            gauge: .value(
                MenuBarGaugeReading(
                    usageRemainingFraction: reading.usageRemainingFraction,
                    timeRemainingFraction: reading.timeRemainingFraction,
                    usageRemainingPercent: reading.usageRemainingPercent,
                    pace: reading.pace
                )
            ),
            limitName: usesCursorModels ? "Cursor models" : "API",
            freshness: freshness
        )
    }
}

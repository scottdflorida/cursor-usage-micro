import Foundation

enum SnapshotOutput {
    static func lines(for report: UsageReport, at date: Date = Date()) -> [String] {
        var snapshots: [(name: String, snapshot: UsageSnapshot)] = []
        if let cursorModels = report.cursorModels {
            snapshots.append((name: "cursor_models", snapshot: cursorModels))
        }
        if let api = report.api {
            snapshots.append((name: "api", snapshot: api))
        }

        return snapshots.flatMap { name, snapshot in
            let reading = snapshot.reading(at: date)
            return [
                "\(name)_time_remaining=\(reading.timeRemainingPercent)",
                "\(name)_usage_remaining=\(reading.usageRemainingPercent)",
                "\(name)_resets_at=\(Int(snapshot.resetsAt.timeIntervalSince1970))",
            ]
        }
    }
}

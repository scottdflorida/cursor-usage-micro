import Foundation

enum CursorUsageResponseParsingError: Error, Equatable {
    case invalidResponse
    case usageUnavailable
}

enum CursorUsageResponseParser {
    static func parse(_ data: Data, at date: Date = Date()) throws -> UsageReport {
        let root: ProviderPayload
        do {
            root = try JSONDecoder().decode(ProviderPayload.self, from: data)
        } catch {
            throw CursorUsageResponseParsingError.invalidResponse
        }

        for payload in root.flattened {
            if payload.enabled == false {
                throw CursorUsageResponseParsingError.usageUnavailable
            }
            guard payload.isRecognizable else { continue }
            guard
                let startsAt = payload.billingCycleStart,
                let resetsAt = payload.billingCycleEnd,
                let planUsage = payload.planUsage,
                CurrentPeriodPolicy.accepts(startsAt: startsAt, resetsAt: resetsAt, at: date)
            else {
                continue
            }

            let cursorModelsPercent: Double?
            if let splitPoolPercent = planUsage.cursorModelsPercentUsed {
                cursorModelsPercent = splitPoolPercent
            } else if planUsage.containsSplitPoolFields {
                cursorModelsPercent = nil
            } else {
                cursorModelsPercent =
                    planUsage.totalPercentUsed
                    ?? percentage(
                        numerator: planUsage.includedSpend,
                        denominator: planUsage.limit
                    )
            }
            let cursorModels = cursorModelsPercent.flatMap {
                UsageSnapshot(
                    usedPercent: $0,
                    startsAt: startsAt,
                    resetsAt: resetsAt
                )
            }
            let api = planUsage.apiPercentUsed.flatMap {
                UsageSnapshot(
                    usedPercent: $0,
                    startsAt: startsAt,
                    resetsAt: resetsAt
                )
            }

            if let report = UsageReport(cursorModels: cursorModels, api: api) {
                return report
            }
        }

        throw CursorUsageResponseParsingError.invalidResponse
    }

    private static func percentage(numerator: Double?, denominator: Double?) -> Double? {
        guard let numerator, let denominator, numerator >= 0, denominator > 0 else {
            return nil
        }
        let value = numerator / denominator * 100
        return value.isFinite ? value : nil
    }
}

private enum CurrentPeriodPolicy {
    static let clockTolerance: TimeInterval = 5 * 60
    // Annual plans are plausible; longer windows usually indicate a timestamp or schema mismatch.
    static let maximumWindowDuration: TimeInterval = 370 * 24 * 60 * 60

    static func accepts(startsAt: Date, resetsAt: Date, at date: Date) -> Bool {
        let referenceTime = date.timeIntervalSinceReferenceDate
        let startsAtReferenceTime = startsAt.timeIntervalSinceReferenceDate
        let resetsAtReferenceTime = resetsAt.timeIntervalSinceReferenceDate
        let duration = resetsAt.timeIntervalSince(startsAt)
        guard
            referenceTime.isFinite,
            startsAtReferenceTime.isFinite,
            resetsAtReferenceTime.isFinite,
            duration.isFinite,
            duration > 0
        else {
            return false
        }

        return duration <= maximumWindowDuration
            && startsAtReferenceTime <= referenceTime + clockTolerance
            && resetsAtReferenceTime >= referenceTime - clockTolerance
    }
}

private enum ProviderSchema {
    static let maximumWrapperDepth = 3
    static let wrapperKeys = ["data", "result", "response", "currentPeriodUsage"]
    static let cycleStartKeys = ["billingCycleStart", "cycleStart", "startsAt", "startAt"]
    static let cycleEndKeys = ["billingCycleEnd", "cycleEnd", "resetsAt", "endAt"]
    static let planUsageKeys = ["planUsage", "usagePlan"]
    static let enabledKeys = ["enabled", "usageEnabled"]

    static let cursorModelsPercentKeys = [
        "autoPercentUsed",
        "cursorModelsPercentUsed",
        "firstPartyPercentUsed",
    ]
    static let totalPercentKeys = ["totalPercentUsed"]
    static let apiPercentKeys = ["apiPercentUsed", "apiModelsPercentUsed"]
    static let includedSpendKeys = ["includedSpend", "spendUsed"]
    static let limitKeys = ["limit", "spendLimit"]
}

private struct ProviderPayload: Decodable {
    let billingCycleStart: Date?
    let billingCycleEnd: Date?
    let planUsage: PlanUsage?
    let enabled: Bool?
    let wrappedPayloads: [ProviderPayload]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        billingCycleStart = container.firstDate(for: ProviderSchema.cycleStartKeys)
        billingCycleEnd = container.firstDate(for: ProviderSchema.cycleEndKeys)
        planUsage = container.decodeAll(PlanUsage.self, for: ProviderSchema.planUsageKeys)
            .first(where: \.hasUsage)
        enabled = container.firstBoolean(for: ProviderSchema.enabledKeys)
        if decoder.codingPath.count < ProviderSchema.maximumWrapperDepth {
            wrappedPayloads = container.decodeAll(ProviderPayload.self, for: ProviderSchema.wrapperKeys)
        } else {
            wrappedPayloads = []
        }
    }

    var isRecognizable: Bool {
        billingCycleStart != nil || billingCycleEnd != nil || planUsage != nil
    }

    var flattened: [ProviderPayload] {
        [self] + wrappedPayloads.flatMap(\.flattened)
    }
}

private struct PlanUsage: Decodable {
    let cursorModelsPercentUsed: Double?
    let totalPercentUsed: Double?
    let apiPercentUsed: Double?
    let includedSpend: Double?
    let limit: Double?
    let containsSplitPoolFields: Bool

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        cursorModelsPercentUsed = container.firstNonnegativeDouble(
            for: ProviderSchema.cursorModelsPercentKeys
        )
        totalPercentUsed = container.firstNonnegativeDouble(for: ProviderSchema.totalPercentKeys)
        apiPercentUsed = container.firstNonnegativeDouble(for: ProviderSchema.apiPercentKeys)
        includedSpend = container.firstNonnegativeDouble(for: ProviderSchema.includedSpendKeys)
        limit = container.firstNonnegativeDouble(for: ProviderSchema.limitKeys)
        containsSplitPoolFields = container.containsAnyKey(
            for: ProviderSchema.cursorModelsPercentKeys + ProviderSchema.apiPercentKeys
        )
    }

    var hasUsage: Bool {
        cursorModelsPercentUsed != nil
            || totalPercentUsed != nil
            || apiPercentUsed != nil
            || (includedSpend != nil && limit.map { $0 > 0 } == true)
    }
}

private struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == DynamicCodingKey {
    fileprivate func decodeAll<Value: Decodable>(_ type: Value.Type, for aliases: [String]) -> [Value] {
        matchingKeys(for: aliases).compactMap { try? decode(Value.self, forKey: $0) }
    }

    fileprivate func firstNonnegativeDouble(for aliases: [String]) -> Double? {
        for key in matchingKeys(for: aliases) {
            guard
                let scalar = try? decode(FlexibleScalar.self, forKey: key),
                let value = scalar.doubleValue,
                value.isFinite,
                value >= 0
            else {
                continue
            }
            return value
        }
        return nil
    }

    fileprivate func firstDate(for aliases: [String]) -> Date? {
        for key in matchingKeys(for: aliases) {
            if let date = (try? decode(FlexibleScalar.self, forKey: key))?.dateValue {
                return date
            }
        }
        return nil
    }

    fileprivate func firstBoolean(for aliases: [String]) -> Bool? {
        for key in matchingKeys(for: aliases) {
            if let value = (try? decode(FlexibleScalar.self, forKey: key))?.boolValue {
                return value
            }
        }
        return nil
    }

    fileprivate func containsAnyKey(for aliases: [String]) -> Bool {
        !matchingKeys(for: aliases).isEmpty
    }

    private func matchingKeys(for aliases: [String]) -> [DynamicCodingKey] {
        var matches: [DynamicCodingKey] = []
        for alias in aliases {
            let normalizedAlias = alias.normalizedProviderKey
            let exactKeys = allKeys.filter { $0.stringValue == alias }
            let normalizedKeys = allKeys.filter {
                $0.stringValue != alias
                    && $0.stringValue.normalizedProviderKey == normalizedAlias
            }
            for key in exactKeys + normalizedKeys where !matches.contains(key) {
                matches.append(key)
            }
        }
        return matches
    }
}

private enum FlexibleScalar: Decodable {
    case boolean(Bool)
    case number(Double)
    case string(String)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var doubleValue: Double? {
        switch self {
        case .boolean:
            nil
        case .number(let value):
            value
        case .string(let value):
            Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var boolValue: Bool? {
        switch self {
        case .boolean(let value):
            value
        case .number(let value) where value == 0:
            false
        case .number(let value) where value == 1:
            true
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "false", "0": false
            case "true", "1": true
            default: nil
            }
        case .number:
            nil
        }
    }

    var dateValue: Date? {
        if let seconds = unixSeconds {
            return Date(timeIntervalSince1970: seconds)
        }
        guard case .string(let rawValue) = self else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    private var unixSeconds: TimeInterval? {
        guard let value = doubleValue, value.isFinite else { return nil }
        let magnitude = abs(value)
        // Cursor has emitted milliseconds; accepting other common epochs makes unit-only changes harmless.
        switch magnitude {
        case 100_000_000_000_000_000...:
            return value / 1_000_000_000
        case 100_000_000_000_000...:
            return value / 1_000_000
        case 100_000_000_000...:
            return value / 1_000
        default:
            return value
        }
    }
}

extension String {
    fileprivate var normalizedProviderKey: String {
        String(lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

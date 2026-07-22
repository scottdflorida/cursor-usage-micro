import AppKit
import Foundation

enum AppConfiguration {
    static let name = "Cursor Usage Micro"
    static let popoverTitle = "CURSOR / GROK USAGE"
    static let compactContentSize = NSSize(width: 320, height: 150)
    static let expandedContentSize = NSSize(width: 320, height: 222)
    static let errorContentSize = NSSize(width: 320, height: 110)

    static let automaticRefreshInterval = RefreshConfiguration.minutes * 60
    static let clockRefreshInterval: TimeInterval = 60
    static let requestTimeout: TimeInterval = 12
    static let maximumResponseBytes = 1_048_576
    static let usageEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )
    static let allowedUsageHost = "api2.cursor.sh"

    static func contentSize(cursorModelsAvailable: Bool, apiAvailable: Bool) -> NSSize {
        cursorModelsAvailable && apiAvailable ? expandedContentSize : compactContentSize
    }

    static func isAllowedUsageEndpoint(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == allowedUsageHost
            && (url.port == nil || url.port == 443)
    }
}

import Foundation

enum RefreshFailurePolicy {
    static func preservesLastReport(
        for error: any Error,
        report: UsageReport,
        at date: Date = Date()
    ) -> Bool {
        report.hasUnexpiredUsage(at: date) && preservesLastReport(for: error)
    }

    static func preservesLastReport(for error: any Error) -> Bool {
        if let error = error as? CursorUsageClientError {
            switch error {
            case .loginExpired, .usageUnavailable:
                return false
            case .connectionFailed, .timedOut, .rateLimited, .serverUnavailable,
                .responseTooLarge, .invalidResponse:
                return true
            }
        }

        if let error = error as? CursorCredentialStoreError {
            switch error {
            case .couldNotReadDatabase:
                return true
            case .databaseNotFound, .notSignedIn, .invalidCredential:
                return false
            }
        }

        return false
    }
}

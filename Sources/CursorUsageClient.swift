import Foundation

protocol UsageFetching: Sendable {
    func fetch() async throws -> UsageReport
}

protocol HTTPDataLoading: Sendable {
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse)
}

enum HTTPDataLoadingError: Error, Equatable {
    case responseTooLarge
}

struct CursorUsageClient: UsageFetching {
    private let credentialStore: any CursorCredentialReading
    private let dataLoader: any HTTPDataLoading
    private let endpoint: URL?
    private let timeout: TimeInterval
    private let maximumResponseBytes: Int
    private let currentDate: @Sendable () -> Date

    init(
        credentialStore: any CursorCredentialReading = CursorCredentialStore(),
        timeout: TimeInterval = AppConfiguration.requestTimeout,
        maximumResponseBytes: Int = AppConfiguration.maximumResponseBytes,
        endpoint: URL? = nil,
        dataLoader: (any HTTPDataLoading)? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentialStore = credentialStore
        self.timeout = timeout
        self.maximumResponseBytes = maximumResponseBytes
        self.endpoint = endpoint ?? AppConfiguration.usageEndpoint
        self.dataLoader = dataLoader ?? URLSessionDataLoader(timeout: timeout)
        self.currentDate = currentDate
    }

    func fetch() async throws -> UsageReport {
        guard
            let endpoint,
            AppConfiguration.isAllowedUsageEndpoint(endpoint),
            timeout > 0,
            maximumResponseBytes > 0
        else {
            throw CursorUsageClientError.invalidResponse
        }
        let accessToken = try credentialStore.readAccessToken()

        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader.data(
                for: request,
                maximumBytes: maximumResponseBytes
            )
        } catch HTTPDataLoadingError.responseTooLarge {
            throw CursorUsageClientError.responseTooLarge
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                // URLSession can report .cancelled without task cancellation; only genuine cancellation stays silent.
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw CursorUsageClientError.connectionFailed
            case .timedOut:
                throw CursorUsageClientError.timedOut
            default:
                throw CursorUsageClientError.connectionFailed
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CursorUsageClientError.connectionFailed
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorUsageClientError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw CursorUsageClientError.loginExpired
        case 408, 504:
            throw CursorUsageClientError.timedOut
        case 429:
            throw CursorUsageClientError.rateLimited
        default:
            throw CursorUsageClientError.serverUnavailable
        }

        guard data.count <= maximumResponseBytes else {
            throw CursorUsageClientError.responseTooLarge
        }

        do {
            return try CursorUsageResponseParser.parse(data, at: currentDate())
        } catch CursorUsageResponseParsingError.usageUnavailable {
            throw CursorUsageClientError.usageUnavailable
        } catch {
            throw CursorUsageClientError.invalidResponse
        }
    }
}

private struct URLSessionDataLoader: HTTPDataLoading {
    private let timeout: TimeInterval

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(
            configuration: configuration,
            delegate: RedirectRejectingSessionDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode != 200
        {
            return (Data(), response)
        }
        if response.expectedContentLength > Int64(maximumBytes) {
            throw HTTPDataLoadingError.responseTooLarge
        }

        var data = Data()
        data.reserveCapacity(min(maximumBytes, 64 * 1_024))

        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw HTTPDataLoadingError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, response)
    }
}

private final class RedirectRejectingSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Never follow redirects: the Authorization bearer token must not be replayed to another host.
        completionHandler(nil)
    }
}

enum CursorUsageClientError: LocalizedError, Equatable {
    case connectionFailed
    case timedOut
    case loginExpired
    case rateLimited
    case serverUnavailable
    case usageUnavailable
    case responseTooLarge
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            "Could not connect to Cursor"
        case .timedOut:
            "Cursor did not respond"
        case .loginExpired:
            "Cursor login expired; open Cursor and sign in again"
        case .rateLimited:
            "Cursor is temporarily limiting usage checks"
        case .serverUnavailable:
            "Cursor usage is temporarily unavailable"
        case .usageUnavailable:
            "Cursor did not provide usage for this account"
        case .responseTooLarge:
            "Cursor returned an unexpectedly large usage response"
        case .invalidResponse:
            "Cursor returned an unfamiliar usage response"
        }
    }
}

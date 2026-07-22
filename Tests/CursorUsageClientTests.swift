import Foundation

func cursorUsageClientTests() -> [TestCase] {
    let endpoint = AppConfiguration.usageEndpoint
    guard let endpoint else {
        preconditionFailure("Invalid Cursor endpoint test fixture")
    }

    let validResponse = Data(
        """
        {
          "billingCycleStart": 1700000000000,
          "billingCycleEnd": 1702678400000,
          "planUsage": {"autoPercentUsed": 25}
        }
        """.utf8
    )
    let responseDate = Date(timeIntervalSince1970: 1_701_000_000)

    func client(
        result: StubHTTPResult,
        maximumResponseBytes: Int = AppConfiguration.maximumResponseBytes,
        recorder: RequestRecorder? = nil
    ) -> CursorUsageClient {
        CursorUsageClient(
            credentialStore: StubCredentialStore(token: "secret-token"),
            maximumResponseBytes: maximumResponseBytes,
            endpoint: endpoint,
            dataLoader: StubHTTPDataLoader(result: result, recorder: recorder),
            currentDate: { responseDate }
        )
    }

    return [
        TestCase(name: "client sends a bounded authenticated JSON request") {
            let recorder = RequestRecorder()
            let report = try await client(
                result: .response(data: validResponse, statusCode: 200),
                recorder: recorder
            ).fetch()
            try expectEqual(report.cursorModels?.usedPercent, 25)

            let request = await recorder.request
            try expectEqual(request?.url, endpoint)
            try expectEqual(request?.httpMethod, "POST")
            try expectEqual(request?.httpBody, Data("{}".utf8))
            try expectEqual(request?.value(forHTTPHeaderField: "Accept"), "application/json")
            try expectEqual(
                request?.value(forHTTPHeaderField: "Authorization"),
                "Bearer secret-token"
            )
            try expectEqual(request?.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)

            // URLSessionDataLoader's streaming cap is network-bound; the bound it receives is pinned here instead.
            let maximumBytes = await recorder.maximumBytes
            try expectEqual(maximumBytes, AppConfiguration.maximumResponseBytes)
        },
        TestCase(name: "client maps authentication and rate-limit responses") {
            try await expectAsyncThrows(CursorUsageClientError.loginExpired) {
                _ = try await client(
                    result: .response(data: Data(), statusCode: 401)
                ).fetch()
            }
            try await expectAsyncThrows(CursorUsageClientError.rateLimited) {
                _ = try await client(
                    result: .response(data: Data(), statusCode: 429)
                ).fetch()
            }
        },
        TestCase(name: "client maps HTTP status failures to their refresh-policy cases") {
            try await expectAsyncThrows(CursorUsageClientError.loginExpired) {
                _ = try await client(result: .response(data: Data(), statusCode: 403)).fetch()
            }
            try await expectAsyncThrows(CursorUsageClientError.timedOut) {
                _ = try await client(result: .response(data: Data(), statusCode: 408)).fetch()
            }
            try await expectAsyncThrows(CursorUsageClientError.timedOut) {
                _ = try await client(result: .response(data: Data(), statusCode: 504)).fetch()
            }
            try await expectAsyncThrows(CursorUsageClientError.serverUnavailable) {
                _ = try await client(result: .response(data: Data(), statusCode: 500)).fetch()
            }
        },
        TestCase(name: "client maps transport failures to their refresh-policy cases") {
            try await expectAsyncThrows(CursorUsageClientError.timedOut) {
                _ = try await client(result: .urlError(.timedOut)).fetch()
            }
            try await expectAsyncThrows(CursorUsageClientError.connectionFailed) {
                _ = try await client(result: .urlError(.notConnectedToInternet)).fetch()
            }
        },
        TestCase(name: "client treats spurious URL cancellation as a connection failure") {
            try await expectAsyncThrows(CursorUsageClientError.connectionFailed) {
                _ = try await client(result: .urlError(.cancelled)).fetch()
            }
        },
        TestCase(name: "client rejects malformed and non-HTTP responses") {
            try await expectAsyncThrows(CursorUsageClientError.invalidResponse) {
                _ = try await client(
                    result: .response(data: Data("not json".utf8), statusCode: 200)
                ).fetch()
            }
            try await expectAsyncThrows(CursorUsageClientError.invalidResponse) {
                _ = try await client(result: .nonHTTPResponse(data: validResponse)).fetch()
            }
        },
        TestCase(name: "client rejects oversized successful responses before parsing") {
            try await expectAsyncThrows(CursorUsageClientError.responseTooLarge) {
                _ = try await client(
                    result: .response(data: validResponse, statusCode: 200),
                    maximumResponseBytes: 8
                ).fetch()
            }
        },
        TestCase(name: "client preserves provider usage-unavailable semantics") {
            let disabledResponse = Data(
                """
                {
                  "billingCycleStart": 1700000000000,
                  "billingCycleEnd": 1702678400000,
                  "planUsage": {"autoPercentUsed": 1},
                  "enabled": false
                }
                """.utf8
            )
            try await expectAsyncThrows(CursorUsageClientError.usageUnavailable) {
                _ = try await client(
                    result: .response(data: disabledResponse, statusCode: 200)
                ).fetch()
            }
        },
        TestCase(name: "client refuses to send credentials to an unapproved host") {
            guard let unapprovedEndpoint = URL(string: "https://example.com/usage") else {
                throw TestFailure(description: "invalid unapproved endpoint fixture")
            }
            try await expectAsyncThrows(CursorUsageClientError.invalidResponse) {
                _ = try await CursorUsageClient(
                    credentialStore: StubCredentialStore(token: "secret-token"),
                    endpoint: unapprovedEndpoint,
                    dataLoader: StubHTTPDataLoader(
                        result: .response(data: validResponse, statusCode: 200),
                        recorder: nil
                    ),
                    currentDate: { responseDate }
                ).fetch()
            }
        },
        TestCase(name: "usage endpoint allowlist pins scheme, host, and port") {
            let allowed = [
                "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
                "https://api2.cursor.sh:443/usage",
                "https://API2.CURSOR.SH/usage",
            ]
            for candidate in allowed {
                guard let url = URL(string: candidate) else {
                    throw TestFailure(description: "invalid allowlist fixture \(candidate)")
                }
                try expect(
                    AppConfiguration.isAllowedUsageEndpoint(url),
                    "expected \(candidate) to be allowed"
                )
            }

            let rejected = [
                "http://api2.cursor.sh/usage",
                "https://api2.cursor.sh:8443/usage",
                "https://evil-api2.cursor.sh/usage",
                "https://api2.cursor.sh.evil.com/usage",
                "https://API2.CURSOR.SH.evil.com/usage",
                "https://api2.cursor.sh@evil.com/usage",
                "https://evil.com/api2.cursor.sh",
                "file:///api2.cursor.sh/usage",
            ]
            for candidate in rejected {
                guard let url = URL(string: candidate) else {
                    throw TestFailure(description: "invalid allowlist fixture \(candidate)")
                }
                try expect(
                    !AppConfiguration.isAllowedUsageEndpoint(url),
                    "expected \(candidate) to be rejected"
                )
            }
        },
    ]
}

private struct StubCredentialStore: CursorCredentialReading {
    let token: String

    func readAccessToken() throws -> String {
        token
    }
}

private enum StubHTTPResult: Sendable {
    case response(data: Data, statusCode: Int)
    case nonHTTPResponse(data: Data)
    case urlError(URLError.Code)
}

private struct StubHTTPDataLoader: HTTPDataLoading {
    let result: StubHTTPResult
    let recorder: RequestRecorder?

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        await recorder?.record(request, maximumBytes: maximumBytes)

        switch result {
        case .response(let data, let statusCode):
            guard
                let response = HTTPURLResponse(
                    url: request.url ?? URL(fileURLWithPath: "/"),
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )
            else {
                throw TestFailure(description: "could not create HTTP response fixture")
            }
            return (data, response)
        case .nonHTTPResponse(let data):
            let response = URLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"),
                mimeType: "application/json",
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            return (data, response)
        case .urlError(let code):
            throw URLError(code)
        }
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?
    private(set) var maximumBytes: Int?

    func record(_ request: URLRequest, maximumBytes: Int) {
        self.request = request
        self.maximumBytes = maximumBytes
    }
}

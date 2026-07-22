import Foundation
import SQLite3

func cursorCredentialStoreTests() -> [TestCase] {
    [
        TestCase(name: "credential store reads only the Cursor access token") {
            let databaseURL = try makeCredentialDatabase(accessToken: "test-access-token")
            defer { try? FileManager.default.removeItem(at: databaseURL) }

            let token = try CursorCredentialStore(databaseURL: databaseURL).readAccessToken()
            try expectEqual(token, "test-access-token")
        },
        TestCase(name: "credential store reports missing login and database") {
            let databaseURL = try makeCredentialDatabase(accessToken: nil)
            defer { try? FileManager.default.removeItem(at: databaseURL) }

            try expectThrows(CursorCredentialStoreError.notSignedIn) {
                _ = try CursorCredentialStore(databaseURL: databaseURL).readAccessToken()
            }

            let missingURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-cursor-credential-\(UUID().uuidString).sqlite")
            try expectThrows(CursorCredentialStoreError.databaseNotFound) {
                _ = try CursorCredentialStore(databaseURL: missingURL).readAccessToken()
            }
        },
        TestCase(name: "credential store rejects unsafe header values") {
            let databaseURL = try makeCredentialDatabase(accessToken: "token\nInjected: value")
            defer { try? FileManager.default.removeItem(at: databaseURL) }

            try expectThrows(CursorCredentialStoreError.invalidCredential) {
                _ = try CursorCredentialStore(databaseURL: databaseURL).readAccessToken()
            }
        },
        TestCase(name: "credential store reports a corrupt database file") {
            let databaseURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("corrupt-cursor-credential-\(UUID().uuidString).sqlite")
            try Data((0..<1_024).map { UInt8(truncatingIfNeeded: $0) }).write(to: databaseURL)
            defer { try? FileManager.default.removeItem(at: databaseURL) }

            try expectThrows(CursorCredentialStoreError.couldNotReadDatabase) {
                _ = try CursorCredentialStore(databaseURL: databaseURL).readAccessToken()
            }
        },
        TestCase(name: "credential store rejects an oversized token") {
            let databaseURL = try makeCredentialDatabase(
                accessToken: String(repeating: "a", count: 20_000)
            )
            defer { try? FileManager.default.removeItem(at: databaseURL) }

            try expectThrows(CursorCredentialStoreError.invalidCredential) {
                _ = try CursorCredentialStore(databaseURL: databaseURL).readAccessToken()
            }
        },
        TestCase(name: "credential store waits out a briefly locked database") {
            let databaseURL = try makeCredentialDatabase(accessToken: "busy-token")
            defer { try? FileManager.default.removeItem(at: databaseURL) }

            let writer = try ExclusiveWriter(databaseURL: databaseURL)
            defer { writer.close() }
            try writer.execute("BEGIN EXCLUSIVE")

            // Release the lock mid-read; the store's 1 s busy timeout must absorb the contention.
            let release = Task.detached {
                try await Task.sleep(nanoseconds: 100_000_000)
                try writer.execute("COMMIT")
            }
            let readResult = Result {
                try CursorCredentialStore(databaseURL: databaseURL).readAccessToken()
            }
            try await release.value
            let token = try readResult.get()
            try expectEqual(token, "busy-token")
        },
    ]
}

private final class ExclusiveWriter: @unchecked Sendable {
    private let connection: OpaquePointer

    init(databaseURL: URL) throws {
        var connection: OpaquePointer?
        guard
            sqlite3_open_v2(
                databaseURL.path,
                &connection,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK,
            let connection
        else {
            if connection != nil {
                sqlite3_close(connection)
            }
            throw TestFailure(description: "could not open SQLite writer fixture")
        }
        self.connection = connection
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestFailure(description: "writer fixture could not execute \(sql)")
        }
    }

    func close() {
        sqlite3_close(connection)
    }
}

private func makeCredentialDatabase(accessToken: String?) throws -> URL {
    let databaseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cursor-credential-\(UUID().uuidString).sqlite")
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
        throw TestFailure(description: "could not create SQLite fixture")
    }
    defer { sqlite3_close(database) }

    guard sqlite3_exec(database, "CREATE TABLE ItemTable (key TEXT, value TEXT)", nil, nil, nil) == SQLITE_OK else {
        throw TestFailure(description: "could not create SQLite fixture table")
    }
    if let accessToken {
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database,
                "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
                -1,
                &statement,
                nil
            ) == SQLITE_OK,
            let statement
        else {
            throw TestFailure(description: "could not prepare SQLite fixture insert")
        }
        defer { sqlite3_finalize(statement) }

        // SQLITE_TRANSIENT; the C macro isn't imported into Swift.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard
            sqlite3_bind_text(statement, 1, "cursorAuth/accessToken", -1, transient) == SQLITE_OK,
            sqlite3_bind_text(statement, 2, accessToken, -1, transient) == SQLITE_OK,
            sqlite3_step(statement) == SQLITE_DONE
        else {
            throw TestFailure(description: "could not insert SQLite fixture token")
        }
    }
    return databaseURL
}

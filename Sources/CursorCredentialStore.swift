import Foundation
import SQLite3

protocol CursorCredentialReading: Sendable {
    func readAccessToken() throws -> String
}

struct CursorCredentialStore: CursorCredentialReading {
    private static let accessTokenKey = "cursorAuth/accessToken"
    private static let maximumTokenBytes: Int32 = 16_384
    private static let query = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"

    private let databaseURL: URL

    init(databaseURL: URL = Self.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    func readAccessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CursorCredentialStoreError.databaseNotFound
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            if database != nil {
                sqlite3_close(database)
            }
            throw CursorCredentialStoreError.couldNotReadDatabase
        }
        defer { sqlite3_close(database) }

        // Cursor writes this WAL database while running; wait briefly instead of failing on SQLITE_BUSY.
        sqlite3_busy_timeout(database, 1_000)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, Self.query, -1, &statement, nil) == SQLITE_OK,
            let statement
        else {
            throw CursorCredentialStoreError.couldNotReadDatabase
        }
        defer { sqlite3_finalize(statement) }

        // SQLITE_TRANSIENT; the C macro isn't imported into Swift.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, Self.accessTokenKey, -1, transient) == SQLITE_OK else {
            throw CursorCredentialStoreError.couldNotReadDatabase
        }
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_ROW else {
            if stepResult != SQLITE_DONE {
                throw CursorCredentialStoreError.couldNotReadDatabase
            }
            throw CursorCredentialStoreError.notSignedIn
        }
        guard let tokenBytes = sqlite3_column_text(statement, 0) else {
            throw CursorCredentialStoreError.notSignedIn
        }

        let byteCount = sqlite3_column_bytes(statement, 0)
        guard byteCount > 0 else {
            throw CursorCredentialStoreError.notSignedIn
        }
        guard byteCount <= Self.maximumTokenBytes else {
            throw CursorCredentialStoreError.invalidCredential
        }

        let tokenData = Data(bytes: tokenBytes, count: Int(byteCount))
        guard let rawToken = String(data: tokenData, encoding: .utf8) else {
            throw CursorCredentialStoreError.invalidCredential
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw CursorCredentialStoreError.notSignedIn
        }
        guard
            !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw CursorCredentialStoreError.invalidCredential
        }
        return token
    }

    private static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
            .appendingPathComponent("state.vscdb")
    }
}

enum CursorCredentialStoreError: LocalizedError, Equatable {
    case databaseNotFound
    case couldNotReadDatabase
    case notSignedIn
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            "Cursor is not installed or has not been opened"
        case .couldNotReadDatabase:
            "Could not read the local Cursor login"
        case .notSignedIn:
            "Open Cursor and sign in to view usage"
        case .invalidCredential:
            "Cursor's local login data is invalid; open Cursor and sign in again"
        }
    }
}

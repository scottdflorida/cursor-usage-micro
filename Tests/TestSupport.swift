import Foundation

struct TestCase {
    let name: String
    let body: () async throws -> Void
}

func expectAsyncThrows<E: Error & Equatable>(
    _ expected: E,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async throws {
    do {
        try await body()
        throw TestFailure(description: "\(file):\(line): expected \(expected), but no error was thrown")
    } catch let error as E {
        try expectEqual(error, expected, file: file, line: line)
    } catch {
        throw TestFailure(
            description: "\(file):\(line): expected \(expected), got \(String(describing: error))"
        )
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard condition() else {
        throw TestFailure(description: "\(file):\(line): \(message())")
    }
}

func expectEqual<T: Equatable>(
    _ actual: @autoclosure () -> T,
    _ expected: @autoclosure () -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let actualValue = actual()
    let expectedValue = expected()
    try expect(
        actualValue == expectedValue,
        "expected \(String(describing: expectedValue)), got \(String(describing: actualValue))",
        file: file,
        line: line
    )
}

func expectThrows<E: Error & Equatable>(
    _ expected: E,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () throws -> Void
) throws {
    do {
        try body()
        throw TestFailure(description: "\(file):\(line): expected \(expected), but no error was thrown")
    } catch let error as E {
        try expectEqual(error, expected, file: file, line: line)
    } catch {
        throw TestFailure(
            description: "\(file):\(line): expected \(expected), got \(String(describing: error))"
        )
    }
}

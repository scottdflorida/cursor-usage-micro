import AppKit
import Darwin
import Foundation

@main
enum CursorUsageMicro {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--snapshot") {
            printSnapshot()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.run()
    }

    private nonisolated static func printSnapshot() {
        let resultBox = SnapshotResultBox()
        let completed = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do {
                resultBox.store(.success(try await CursorUsageClient().fetch()))
            } catch {
                resultBox.store(.failure(error.localizedDescription))
            }
            completed.signal()
        }
        completed.wait()

        switch resultBox.load() {
        case .success(let report):
            for line in SnapshotOutput.lines(for: report) {
                print(line)
            }
        case .failure(let diagnostic):
            fputs("\(diagnostic)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private enum SnapshotResult: Sendable {
    case success(UsageReport)
    case failure(String)
}

private final class SnapshotResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: SnapshotResult?

    func store(_ result: SnapshotResult) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> SnapshotResult {
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            preconditionFailure("Snapshot result was read before completion")
        }
        return result
    }
}

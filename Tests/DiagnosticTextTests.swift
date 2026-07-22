import Foundation

func diagnosticTextTests() -> [TestCase] {
    [
        TestCase(name: "diagnostics are single-line, bounded, and never empty") {
            try expectEqual(DiagnosticText.sanitized("  network\n  unavailable  "), "network unavailable")
            try expectEqual(DiagnosticText.sanitized(" \n\t "), "Cursor returned an error")

            let diagnostic = DiagnosticText.sanitized(String(repeating: "x", count: 500))
            try expectEqual(diagnostic.count, DiagnosticText.maximumLength)
            try expect(diagnostic.hasSuffix("…"), "expected a visible truncation marker")
        },
        TestCase(name: "control characters and home paths never reach diagnostics") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            try expectEqual(
                DiagnosticText.sanitized("token\u{07} rejected\u{9B} at \(home)/Library"),
                "token rejected at ~/Library"
            )
        },
    ]
}

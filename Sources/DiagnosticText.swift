import Foundation

enum DiagnosticText {
    static let maximumLength = 240

    static func sanitized(_ message: String) -> String {
        let flattened =
            message
            .replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let cleaned = String(
            String.UnicodeScalarView(
                flattened.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            )
        )

        guard !cleaned.isEmpty else {
            return "Cursor returned an error"
        }
        guard cleaned.count > maximumLength else {
            return cleaned
        }

        return cleaned.prefix(maximumLength - 1) + "…"
    }
}

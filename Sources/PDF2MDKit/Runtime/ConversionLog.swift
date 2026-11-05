import Darwin
import Foundation

/// One line per file in the log. Each is a single `O_APPEND` write, so concurrent runs can't
/// interleave within a line.
public struct ConversionLog: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func append(_ outcome: FileOutcome, date: Date = Date()) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let data = Data((Self.line(for: outcome, date: date) + "\n").utf8)
        _ = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    static func line(for outcome: FileOutcome, date: Date) -> String {
        let stats = outcome.stats
        var fields = [
            ISO8601DateFormatter().string(from: date),
            outcome.error == nil ? "ok" : "failed",
            "file=\(quoted(outcome.input.lastPathComponent))",
            "pages=\(stats.pages)",
            "ocr=\(stats.ocrPages)",
            "tables=\(stats.tables)",
            "images=\(stats.images)",
            "math=\(stats.mathSpans)",
            "duration=\(String(format: "%.1f", outcome.duration))s",
        ]
        if let output = outcome.output { fields.append("output=\(quoted(output))") }
        if let error = outcome.error { fields.append("error=\(quoted(error))") }
        if stats.failedPages > 0 { fields.append("failed_pages=\(stats.failedPages)") }
        if let note = stats.firstNote { fields.append("note=\(quoted(note))") }
        return fields.joined(separator: " ")
    }

    private static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}

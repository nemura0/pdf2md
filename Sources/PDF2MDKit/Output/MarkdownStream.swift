import Foundation

/// Streams blocks to disk in order, guaranteeing the output's whitespace invariants: one blank
/// line between blocks, no double blanks, no trailing spaces, one final newline.
public struct MarkdownStream {
    private static let flushThreshold = 64 * 1024

    private let handle: FileHandle
    private var buffer = Data()
    private var hasContent = false

    public init(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw ConversionFailure("couldn't create \(url.lastPathComponent)")
            }
        }
        self.handle = try FileHandle(forWritingTo: url)
    }

    public mutating func write(block: String) throws {
        let cleaned = Self.clean(block)
        guard !cleaned.isEmpty else { return }
        if hasContent { buffer.append(Data("\n\n".utf8)) }
        buffer.append(Data(cleaned.utf8))
        hasContent = true
        if buffer.count >= Self.flushThreshold { try flush() }
    }

    public mutating func close() throws {
        if hasContent { buffer.append(Data("\n".utf8)) }
        try flush()
        try handle.close()
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private static func clean(_ block: String) -> String {
        var lines: [Substring] = []
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            var trimmed = line
            while let last = trimmed.last, last == " " || last == "\t" || last == "\r" {
                trimmed = trimmed.dropLast()
            }
            if trimmed.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(trimmed)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

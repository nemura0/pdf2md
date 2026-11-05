import Foundation

public struct DocumentTitle: Sendable, Equatable {
    public var text: String
    /// Page 1 lines that are the title. They leave the flow, so `#` isn't repeated as text.
    public var lineTexts: [String]

    public init(text: String, lineTexts: [String]) {
        self.text = text
        self.lineTexts = lineTexts
    }
}

/// Picks the document title: useful metadata, then the largest text on page 1, then the file name.
public enum TitleResolver {
    /// Text must be clearly larger than body text to be the title.
    private static let minimumSizeRatio = 1.15
    private static let minimumLetters = 4
    private static let maximumTitleLines = 3
    private static let sameSizeTolerance = 0.5
    /// A title line's successor sits within this many font sizes.
    private static let maximumLineGap = 2.0

    private static let fileExtensions: Set<String> = [
        "pdf", "doc", "docx", "ppt", "pptx", "tex", "dvi", "ps", "indd", "odt", "odp", "txt", "key",
        "rtf", "pages", "xls", "xlsx",
    ]

    public static func isMeaningful(metadataTitle: String) -> Bool {
        let title = metadataTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = title.lowercased()
        guard title.filter(\.isLetter).count >= minimumLetters else { return false }
        if lowered.hasPrefix("untitled") || lowered.hasPrefix("microsoft ") { return false }
        if lowered.contains("powerpoint") { return false }
        if lowered.wholeMatch(of: /(slide|diapositiva|page|p[aá]gina)\s*\d*/) != nil {
            return false
        }
        if title.contains("/") || title.contains("\\") { return false }
        let pathExtension = (lowered as NSString).pathExtension
        return !fileExtensions.contains(pathExtension)
    }

    public static func resolve(
        metadataTitle: String?,
        firstPageLines: [TextLine],
        bodySize: Double,
        fileName: String
    ) -> DocumentTitle {
        let largest = largestLines(in: firstPageLines, bodySize: bodySize)
        if let metadataTitle, isMeaningful(metadataTitle: metadataTitle) {
            let text = clean(metadataTitle)
            return DocumentTitle(
                text: text,
                lineTexts: matchingLines(largest, in: firstPageLines, title: text)
            )
        }
        guard !largest.isEmpty else {
            return DocumentTitle(text: clean(fileName), lineTexts: [])
        }
        return DocumentTitle(
            text: clean(largest.map(\.text).joined(separator: " ")),
            lineTexts: largest.map(\.text)
        )
    }

    /// The contiguous group of the largest text, reading from the top.
    private static func largestLines(in lines: [TextLine], bodySize: Double) -> [TextLine] {
        let candidates = lines.filter { $0.text.contains(where: \.isLetter) }
        guard let largestSize = candidates.map(\.size).max(),
            largestSize >= bodySize * minimumSizeRatio
        else { return [] }

        let sorted = candidates.sorted { $0.baseline < $1.baseline }
        guard
            let start = sorted.firstIndex(where: { abs($0.size - largestSize) < sameSizeTolerance })
        else { return [] }
        var group = [sorted[start]]
        for line in sorted[(start + 1)...] {
            guard group.count < maximumTitleLines,
                abs(line.size - largestSize) < sameSizeTolerance,
                let previous = group.last,
                line.baseline - previous.baseline <= largestSize * maximumLineGap
            else { break }
            group.append(line)
        }
        return group
    }

    private static func matchingLines(
        _ largest: [TextLine],
        in lines: [TextLine],
        title: String
    ) -> [String] {
        let target = comparable(title)
        let joined = comparable(largest.map(\.text).joined(separator: " "))
        if !largest.isEmpty, joined == target { return largest.map(\.text) }
        return lines.first { comparable($0.text) == target }.map { [$0.text] } ?? []
    }

    static func comparable(_ text: String) -> String {
        TextNormalizer.normalize(text).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func clean(_ text: String) -> String {
        TextNormalizer.normalize(text)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

import Foundation

/// One entry of a PDF's outline. Read in preflight, so emit never opens the file (A4).
public struct OutlineEntry: Sendable, Equatable {
    public var pageIndex: Int
    public var depth: Int
    public var label: String

    public init(pageIndex: Int, depth: Int, label: String) {
        self.pageIndex = pageIndex
        self.depth = depth
        self.label = label
    }
}

public enum OutlineLabel {
    /// Tidies a label as PDFs store it. A `\colorbox` in a LaTeX heading leaks into the outline as
    /// `=0ptdarkgray!20final`: 4 of the 241 entries in a real book, all naming code.
    public static func clean(_ raw: String) -> String {
        let withoutResidue = raw.replacing(/=[\d.]+(?:pt|em|ex|cm|mm)(?:[A-Za-z]+!\d+)?/, with: "")
        return TextNormalizer.normalize(withoutResidue)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// Finds the lines a page's outline entries name. The outline only says which line is a heading
/// and how deep. The text stays as printed, because that's where a section's number is (ADR-0009).
enum OutlineMatcher {
    private static let topLevel = 2
    private static let deepestLevel = 6
    /// What a printed line can add in front of its label: `1.14.3.` or `Capitulo 12`.
    private static let maximumPrefixLength = 12
    private static let maximumRunLines = 3
    private static let maximumNumberWords = 3
    /// Chapter openers set the number and the title far apart: 58 points at 24.8 in a real book.
    private static let maximumLineGap = 3.0

    static func level(forDepth depth: Int) -> Int {
        min(topLevel + max(depth, 0), deepestLevel)
    }

    /// Returns the lines top to bottom with each entry's line marked, merging a title on several
    /// lines and the chapter number above it. A heading is at least `minimumSize` or bold. Without
    /// `joinsNumbers`, the lines marked show the style of the title alone.
    static func marking(
        _ lines: [TextLine],
        with entries: [OutlineEntry],
        minimumSize: Double,
        joinsNumbers: Bool = true
    ) -> [TextLine] {
        guard !entries.isEmpty else { return lines }
        var sorted = lines.sorted {
            ($0.baseline, Double($0.rect.minX)) < ($1.baseline, Double($1.rect.minX))
        }
        for entry in entries {
            let target = TitleResolver.comparable(entry.label)
            guard !target.isEmpty,
                let run = bestRun(for: target, in: sorted, minimumSize: minimumSize)
            else { continue }
            let hasNumber =
                joinsNumbers && hasNumberLine(before: run.lowerBound, in: sorted, minimumSize)
            let start = hasNumber ? run.lowerBound - 1 : run.lowerBound
            var heading = TextLine(words: sorted[start..<run.upperBound].flatMap(\.words))
            heading.outlineLevel = level(forDepth: entry.depth)
            sorted.replaceSubrange(start..<run.upperBound, with: [heading])
        }
        return sorted
    }

    /// The run of lines reading as the label whose last line is the largest, the shortest among
    /// equals. A running header on the page often holds the same words, in smaller type.
    private static func bestRun(
        for target: String,
        in lines: [TextLine],
        minimumSize: Double
    ) -> Range<Int>? {
        var best: (range: Range<Int>, size: Double)?
        for start in lines.indices {
            guard let run = run(from: start, for: target, in: lines, minimumSize: minimumSize)
            else { continue }
            guard let current = best else {
                best = run
                continue
            }
            let isShorter = run.size == current.size && run.range.count < current.range.count
            if run.size > current.size || isShorter { best = run }
        }
        return best?.range
    }

    private static func run(
        from start: Int,
        for target: String,
        in lines: [TextLine],
        minimumSize: Double
    ) -> (range: Range<Int>, size: Double)? {
        var joined = ""
        for end in start..<min(start + maximumRunLines, lines.count) {
            let line = lines[end]
            guard line.outlineLevel == nil, line.size >= minimumSize || line.isBold,
                end == start || isClose(lines[end - 1], line)
            else { return nil }
            joined += TitleResolver.comparable(line.text)
            guard joined.count <= target.count + maximumPrefixLength else { return nil }
            if joined.hasSuffix(target) { return (start..<(end + 1), line.size) }
        }
        return nil
    }

    private static func isClose(_ first: TextLine, _ second: TextLine) -> Bool {
        second.baseline - first.baseline <= max(first.size, second.size) * maximumLineGap
    }

    /// A chapter's number on its own line above the title, or a line like `Capitulo 3` or
    /// `Apendice A`. It has to be set large: a page number above a heading is at the size of the
    /// text.
    private static func hasNumberLine(
        before index: Int,
        in lines: [TextLine],
        _ minimumSize: Double
    ) -> Bool {
        guard index > 0 else { return false }
        let above = lines[index - 1]
        return above.outlineLevel == nil && above.size >= minimumSize
            && above.words.count <= maximumNumberWords
            && TitleResolver.comparable(above.text).count <= maximumPrefixLength
            && endsInNumber(above.text)
            && isClose(above, lines[index])
    }

    private static func endsInNumber(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let last = lowered.split(whereSeparator: \.isWhitespace).last
        return last?.count == 1 || MarginFilter.key(for: lowered) != lowered
    }
}

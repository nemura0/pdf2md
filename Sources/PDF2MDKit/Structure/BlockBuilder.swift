import CoreGraphics
import Foundation

/// Turns ordered lines into document structure: headings, lists, code and reflowed paragraphs.
public struct BlockBuilder: Sendable {
    /// A gap this many times the typical leading starts a new paragraph.
    private static let paragraphGapRatio = 1.35
    private static let maximumHeadingLength = 200
    private static let maximumBoldHeadingLength = 100
    private static let maximumHeadingLines = 3
    private static let headingLineGap = 1.6
    /// A first-line indent is at least this many font sizes.
    private static let indentRatio = 0.8
    /// A line ending this far from the right edge, with terminal punctuation, ends its paragraph.
    private static let shortLineShare = 0.15
    private static let sizeChangeRatio = 1.1
    private static let positionTolerance = 3.0
    /// A slide title is clearly larger than the slide's text.
    private static let slideTitleRatio = 1.15

    private let profile: DocumentProfile

    public init(profile: DocumentProfile) {
        self.profile = profile
    }

    /// A page can arrive in pieces around a table or a figure. Only its first piece has a title.
    public func blocks(
        from lines: [TextLine],
        isSlidePage: Bool,
        allowsSlideTitle: Bool = true
    ) -> [Block] {
        var state = BuildState(lines: lines)
        let slideTitle = isSlidePage && allowsSlideTitle ? slideTitleLine(in: lines) : nil

        for (index, line) in lines.enumerated() {
            if line.isMonospace {
                state.addCode(line)
            } else if let level = headingLevel(
                for: line,
                isSlidePage: isSlidePage,
                isSlideTitle: index == slideTitle
            ) {
                state.addHeading(line, level: level)
            } else if let item = listStart(in: line) {
                state.addListItem(item, line: line)
            } else if state.continuesList(line) {
                state.continueList(line)
            } else {
                state.addText(line)
            }
        }
        state.flush()
        return state.blocks
    }

    /// The top line, if it's clearly larger than the rest of the slide or set in bold.
    private func slideTitleLine(in lines: [TextLine]) -> Int? {
        guard let first = lines.indices.min(by: { lines[$0].baseline < lines[$1].baseline }) else {
            return nil
        }
        let line = lines[first]
        guard line.text.contains(where: \.isLetter), !line.isMonospace,
            listStart(in: line) == nil
        else { return nil }
        let isLargest = lines.allSatisfy { $0.size <= line.size + 0.5 }
        let isClearlyLarge = line.size >= profile.bodySize * Self.slideTitleRatio
        return (isLargest && (isClearlyLarge || line.isBold)) ? first : nil
    }

    private func headingLevel(for line: TextLine, isSlidePage: Bool, isSlideTitle: Bool) -> Int? {
        if isSlideTitle { return 2 }
        guard line.text.contains(where: \.isLetter), line.text.count <= Self.maximumHeadingLength,
            listStart(in: line) == nil
        else { return nil }
        if isSlidePage {
            // `##` is reserved for slide titles, and slides set much of their text large, so a
            // large line that reads as a sentence is text.
            guard let level = profile.headingLevel(forSize: line.size),
                let last = line.text.last, !".,;:".contains(last)
            else { return nil }
            return max(level, 3)
        }
        if let level = profile.headingLevel(forSize: line.size) { return level }
        if line.isBold, abs(line.size - profile.bodySize) < 1,
            line.text.count <= Self.maximumBoldHeadingLength,
            let last = line.text.last, !".,;:".contains(last)
        {
            return profile.boldHeadingLevel
        }
        return nil
    }

    private func listStart(in line: TextLine) -> PendingItem? {
        guard let first = line.words.first else { return nil }
        if let marker = ListMarker.marker(forToken: first.text) {
            return PendingItem(
                marker: marker,
                markerX: first.rect.minX,
                textX: Double(line.words.dropFirst().first?.rect.minX ?? first.rect.maxX),
                words: Array(line.words.dropFirst())
            )
        }
        if let rest = ListMarker.attachedBullet(in: first.text) {
            var remainder = first
            remainder.text = rest
            return PendingItem(
                marker: "-",
                markerX: first.rect.minX,
                textX: first.rect.minX + first.size,
                words: [remainder] + line.words.dropFirst()
            )
        }
        return nil
    }

    struct PendingItem: Equatable {
        var marker: String
        var markerX: Double
        var textX: Double
        var words: [Word]
    }

    /// Accumulates the block in progress while walking the lines.
    private struct BuildState {
        var blocks: [Block] = []
        let leading: Double
        let rightEdge: Double
        let leftEdge: Double

        var paragraph = ""
        var paragraphLast: TextLine?
        var heading: (level: Int, text: String, last: TextLine)?
        var codeLines: [TextLine] = []
        var items: [ListItem] = []
        var indentStack: [Double] = []
        var itemTextX = 0.0
        var itemLast: TextLine?

        init(lines: [TextLine]) {
            let gaps = zip(lines, lines.dropFirst())
                .map { $1.baseline - $0.baseline }
                .filter { $0 > 1 }
                .sorted()
            let fallback = (lines.first?.size ?? 10) * 1.2
            self.leading = gaps.isEmpty ? fallback : gaps[(gaps.count - 1) / 2]
            self.rightEdge = Double(lines.map(\.rect.maxX).max() ?? 0)
            self.leftEdge = Double(lines.map(\.rect.minX).min() ?? 0)
        }

        mutating func flush() {
            flushParagraph()
            flushHeading()
            flushCode()
            flushList()
        }

        // MARK: Paragraphs

        mutating func addText(_ line: TextLine) {
            flushHeading()
            flushCode()
            flushList()
            let text = InlineRenderer.render(line.words)
            guard !text.isEmpty else { return }
            if let last = paragraphLast, startsNewParagraph(line, after: last) { flushParagraph() }
            paragraph = paragraph.isEmpty ? text : Self.joining(paragraph, text)
            paragraphLast = line
        }

        private func startsNewParagraph(_ line: TextLine, after last: TextLine) -> Bool {
            let gap = line.baseline - last.baseline
            let ratio = max(line.size, last.size) / max(min(line.size, last.size), 0.1)
            if ratio > BlockBuilder.sizeChangeRatio { return true }
            let endsSentence = last.text.last.map { ".:!?)".contains($0) } ?? false
            if gap < 0 { return endsSentence }  // A column break.
            if gap > leading * BlockBuilder.paragraphGapRatio { return true }

            let indent = line.rect.minX - last.rect.minX
            if indent > line.size * BlockBuilder.indentRatio { return true }
            let width = rightEdge - leftEdge
            let isShort = rightEdge - last.rect.maxX > width * BlockBuilder.shortLineShare
            return isShort && endsSentence
        }

        /// Joins two lines of one paragraph, dropping an end-of-line hyphen before a lowercase
        /// letter. Before a capital it's a real one, as in `Hewlett-Packard`.
        static func joining(_ first: String, _ second: String) -> String {
            guard first.hasSuffix("-"), first.count > 1 else { return first + " " + second }
            if second.first?.isLowercase == true { return String(first.dropLast()) + second }
            return first + second
        }

        mutating func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(InlineRenderer.escapingBlockStart(paragraph)))
            paragraph = ""
            paragraphLast = nil
        }

        // MARK: Headings

        mutating func addHeading(_ line: TextLine, level: Int) {
            flushParagraph()
            flushCode()
            flushList()
            let text = InlineRenderer.render(line.words)
            if let current = heading, current.level == level,
                line.baseline - current.last.baseline <= line.size * BlockBuilder.headingLineGap,
                current.text.count < BlockBuilder.maximumHeadingLength
            {
                heading = (level, current.text + " " + text, line)
            } else {
                flushHeading()
                heading = (level, text, line)
            }
        }

        mutating func flushHeading() {
            guard let current = heading else { return }
            blocks.append(.heading(level: current.level, text: current.text))
            heading = nil
        }

        // MARK: Code

        mutating func addCode(_ line: TextLine) {
            flushParagraph()
            flushHeading()
            flushList()
            codeLines.append(line)
        }

        mutating func flushCode() {
            guard !codeLines.isEmpty else { return }
            blocks.append(.code(CodeLayout.lines(from: codeLines)))
            codeLines = []
        }

        // MARK: Lists

        mutating func addListItem(_ item: PendingItem, line: TextLine) {
            flushParagraph()
            flushHeading()
            flushCode()
            guard !item.words.isEmpty else { return }
            while let top = indentStack.last, top > item.markerX + BlockBuilder.positionTolerance {
                indentStack.removeLast()
            }
            if let top = indentStack.last {
                if item.markerX > top + BlockBuilder.positionTolerance {
                    indentStack.append(item.markerX)
                }
            } else {
                indentStack.append(item.markerX)
            }
            items.append(
                ListItem(
                    depth: indentStack.count - 1,
                    marker: item.marker,
                    text: InlineRenderer.render(item.words)
                )
            )
            itemTextX = item.textX
            itemLast = line
        }

        func continuesList(_ line: TextLine) -> Bool {
            guard let last = itemLast else { return false }
            let gap = line.baseline - last.baseline
            return gap >= 0 && gap <= leading * BlockBuilder.paragraphGapRatio
                && line.rect.minX >= itemTextX - BlockBuilder.positionTolerance
                && abs(line.size - last.size) < 1
        }

        mutating func continueList(_ line: TextLine) {
            guard var item = items.popLast() else { return }
            item.text = Self.joining(item.text, InlineRenderer.render(line.words))
            items.append(item)
            itemLast = line
        }

        mutating func flushList() {
            guard !items.isEmpty else {
                indentStack = []
                itemLast = nil
                return
            }
            blocks.append(.list(items))
            items = []
            indentStack = []
            itemLast = nil
        }
    }
}

/// Rebuilds code text from geometry, since `page.string` collapses spaces (ADR-0003).
enum CodeLayout {
    private static let blankLineRatio = 1.6
    /// A malformed page can place words anywhere, and this much indentation is already absurd.
    private static let maximumSpaces = 200.0

    static func lines(from lines: [TextLine]) -> [String] {
        let cell = characterWidth(in: lines)
        let base = lines.map(\.rect.minX).min() ?? 0
        let gaps = zip(lines, lines.dropFirst()).map { $1.baseline - $0.baseline }.filter { $0 > 1 }
        let leading = gaps.min() ?? 0

        var output: [String] = []
        var previous: TextLine?
        for line in lines {
            if let previous, leading > 0,
                line.baseline - previous.baseline > leading * blankLineRatio
            {
                output.append("")
            }
            output.append(render(line, base: base, cell: cell))
            previous = line
        }
        return output
    }

    private static func render(_ line: TextLine, base: Double, cell: Double) -> String {
        var text = String(repeating: " ", count: spaces(line.rect.minX - base, cell: cell))
        var previous: Word?
        for word in line.words {
            if let previous, !word.isGlued {
                let gap = word.rect.minX - previous.rect.maxX
                text += String(repeating: " ", count: max(1, spaces(gap, cell: cell)))
            }
            text += TextNormalizer.normalize(word.text)
            previous = word
        }
        return text
    }

    private static func spaces(_ distance: Double, cell: Double) -> Int {
        guard cell > 0, distance > 0, distance.isFinite else { return 0 }
        return Int(min((distance / cell).rounded(), maximumSpaces))
    }

    private static func characterWidth(in lines: [TextLine]) -> Double {
        let widths = lines.flatMap(\.words)
            .filter { !$0.text.isEmpty }
            .map { $0.rect.width / Double($0.text.count) }
            .sorted()
        return widths.isEmpty ? 0 : widths[widths.count / 2]
    }
}

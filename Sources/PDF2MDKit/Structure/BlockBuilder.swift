import CoreGraphics
import Foundation

/// Turns ordered lines into document structure: headings, lists, code and reflowed paragraphs.
public struct BlockBuilder: Sendable {
    /// A gap this many times the typical leading starts a new paragraph.
    private static let paragraphGapRatio = 1.35
    private static let leadingTolerance = 0.5
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
    /// Code that wraps from a line of text sits at that text's leading. A real code block has
    /// space above it, or a smaller font.
    private static let wrappedCodeGapRatio = 1.35
    /// A piece of a page between two figures can hold only short lines, and the longest of them
    /// isn't a full line. Even a narrow column is wider than this, in font sizes.
    private static let minimumFullLineSizes = 20.0

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
            let next = index + 1 < lines.count ? lines[index + 1] : nil
            if let level = line.outlineLevel {
                state.addOutlineHeading(line, level: level)
            } else if state.isWrappedCode(line, next: next) {
                state.addWrappedCode(line)
            } else if line.isMonospace || isBlankListingLine(at: index, in: lines) {
                state.addCode(line)
            } else if index != slideTitle, listStart(in: line) == nil,
                let latex = MathSpans.displayLatex(line)
            {
                state.addDisplayMath(latex)
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
                state.addText(line, next: next)
            }
        }
        state.flush()
        return state.blocks
    }

    /// A listing's blank line still has its number, and a line citing it needs that number. It
    /// counts only with numbered code next to it, past any other blank ones.
    private func isBlankListingLine(at index: Int, in lines: [TextLine]) -> Bool {
        guard isNumberAlone(lines[index]) else { return false }
        let before = lines[..<index].last { !isNumberAlone($0) }
        let after = lines[(index + 1)...].first { !isNumberAlone($0) }
        return [before, after].contains { neighbor in
            guard let neighbor, neighbor.lineNumber != nil, neighbor.isMonospace else {
                return false
            }
            return lines[index].size <= neighbor.size
        }
    }

    private func isNumberAlone(_ line: TextLine) -> Bool {
        line.words.count == 1 && TextLine.isPlainNumber(line.words[0])
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
            guard let level = profile.headingLevel(for: line),
                let last = line.text.last, !".,;:".contains(last)
            else { return nil }
            return max(level, 3)
        }
        if let level = profile.headingLevel(for: line) { return level }
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
        /// Each size has its own leading, because code and footnotes share a page with the text.
        let leadingBySize: [Double: Double]
        let fallbackLeading: Double
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
            var gapsBySize: [Double: [Double]] = [:]
            for (first, second) in zip(lines, lines.dropFirst()) where first.size == second.size {
                let gap = second.baseline - first.baseline
                if gap > 1 { gapsBySize[first.size, default: []].append(gap) }
            }
            self.leadingBySize = gapsBySize.mapValues { Self.leading(from: $0) }
            self.fallbackLeading = (lines.first?.size ?? 10) * 1.2
            self.rightEdge = Double(lines.map(\.rect.maxX).max() ?? 0)
            self.leftEdge = Double(lines.map(\.rect.minX).min() ?? 0)
        }

        /// The smallest gap that repeats, since paragraph gaps can outnumber line gaps on a page of
        /// short paragraphs. Measured: half of a page of definitions was gaps of 19.9 against a
        /// leading of 11.9, so a median read paragraphs as lines. A lone gap decides nothing.
        private static func leading(from gaps: [Double]) -> Double {
            let sorted = gaps.sorted()
            for (first, second) in zip(sorted, sorted.dropFirst())
            where second - first <= BlockBuilder.leadingTolerance {
                return first
            }
            return sorted[(sorted.count - 1) / 2]
        }

        private func leading(for line: TextLine) -> Double {
            leadingBySize[line.size] ?? leadingBySize.values.min() ?? fallbackLeading
        }

        mutating func flush() {
            flushParagraph()
            flushHeading()
            flushCode()
            flushList()
        }

        // MARK: Paragraphs

        mutating func addText(_ line: TextLine, next: TextLine?) {
            flushHeading()
            flushCode()
            flushList()
            if let last = paragraphLast, startsNewParagraph(line, after: last, next: next) {
                flushParagraph()
            }
            let isOpening = paragraph.isEmpty
            let text =
                isOpening
                ? InlineRenderer.renderOpening(line.words, in: line)
                : InlineRenderer.render(line: line)
            guard !text.isEmpty else { return }
            paragraph = isOpening ? text : Self.joining(paragraph, text)
            paragraphLast = line
        }

        /// An inline code span too long for its line wraps onto one of its own, which looks just
        /// like a line of code. The line above gives it away: a full line of text at the same
        /// leading can't have ended there.
        func isWrappedCode(_ line: TextLine, next: TextLine?) -> Bool {
            guard line.isMonospace, line.lineNumber == nil, let last = paragraphLast else {
                return false
            }
            let reach = line.size * BlockBuilder.wrappedCodeGapRatio
            let gap = line.baseline - last.baseline
            guard gap > 0, gap <= reach, !isShort(last),
                last.rect.width >= line.size * BlockBuilder.minimumFullLineSizes,
                max(line.size, last.size) / max(min(line.size, last.size), 0.1)
                    <= BlockBuilder.sizeChangeRatio
            else { return false }
            guard let next, next.isMonospace else { return true }
            return next.baseline - line.baseline > reach
        }

        mutating func addWrappedCode(_ line: TextLine) {
            let span = InlineRenderer.code(line.words)
            if Self.endsInURL(paragraph) {
                paragraph = String(paragraph.dropLast()) + span.dropFirst()
            } else {
                paragraph = Self.joining(paragraph, span)
            }
            paragraphLast = line
        }

        /// True when the text ends in a code span holding a URL, the usual thing to wrap.
        private static func endsInURL(_ text: String) -> Bool {
            guard text.hasSuffix("`"),
                let start = text.dropLast().lastIndex(of: "`")
            else { return false }
            let span = text[start...]
            return !span.contains(" ") && (span.contains("://") || span.contains("www."))
        }

        private func isShort(_ line: TextLine) -> Bool {
            rightEdge - line.rect.maxX > (rightEdge - leftEdge) * BlockBuilder.shortLineShare
        }

        private func startsNewParagraph(
            _ line: TextLine,
            after last: TextLine,
            next: TextLine?
        ) -> Bool {
            let gap = line.baseline - last.baseline
            let ratio = max(line.size, last.size) / max(min(line.size, last.size), 0.1)
            if ratio > BlockBuilder.sizeChangeRatio { return true }
            let endsSentence = last.text.last.map { ".:!?)".contains($0) } ?? false
            if gap < 0 { return endsSentence }  // A column break.
            if gap > leading(for: line) * BlockBuilder.paragraphGapRatio { return true }

            let indent = line.rect.minX - last.rect.minX
            if indent > line.size * BlockBuilder.indentRatio {
                return !isHanging(line, after: last, next: next, endsSentence: endsSentence)
            }
            return isShort(last) && endsSentence
        }

        /// Tells a hanging indent from a first-line one. Text that fills its line and doesn't end
        /// a sentence goes on, whatever the indent. If it does end one, a bold term opening the
        /// paragraph settles it, or the line after: only a hanging indent stays indented.
        private func isHanging(
            _ line: TextLine,
            after last: TextLine,
            next: TextLine?,
            endsSentence: Bool
        ) -> Bool {
            guard !isShort(last) else { return false }
            guard endsSentence, !paragraph.hasPrefix("**") else { return true }
            guard let next else { return false }
            return abs(next.rect.minX - line.rect.minX) <= BlockBuilder.positionTolerance
                && next.baseline - line.baseline
                    <= leading(for: line) * BlockBuilder.paragraphGapRatio
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
            let text = InlineRenderer.render(line: line)
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

        /// The outline already joined this heading's lines, and the next heading is another one
        /// however close it sits.
        mutating func addOutlineHeading(_ line: TextLine, level: Int) {
            flushParagraph()
            flushCode()
            flushList()
            flushHeading()
            heading = (level, InlineRenderer.render(line: line), line)
            flushHeading()
        }

        mutating func flushHeading() {
            guard let current = heading else { return }
            blocks.append(.heading(level: current.level, text: current.text))
            heading = nil
        }

        // MARK: Math

        mutating func addDisplayMath(_ latex: String) {
            flush()
            blocks.append(.displayMath(latex))
        }

        // MARK: Code

        mutating func addCode(_ line: TextLine) {
            flushParagraph()
            flushHeading()
            flushList()
            if CodeLayout.startsOver(line, after: codeLines) { flushCode() }
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
                    text: InlineRenderer.renderOpening(item.words, in: line)
                )
            )
            itemTextX = item.textX
            itemLast = line
        }

        func continuesList(_ line: TextLine) -> Bool {
            guard let last = itemLast else { return false }
            let gap = line.baseline - last.baseline
            return gap >= 0 && gap <= leading(for: line) * BlockBuilder.paragraphGapRatio
                && line.rect.minX >= itemTextX - BlockBuilder.positionTolerance
                && abs(line.size - last.size) < 1
        }

        mutating func continueList(_ line: TextLine) {
            guard var item = items.popLast() else { return }
            item.text = Self.joining(item.text, InlineRenderer.render(line: line))
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
    private static let indentStepTolerance = 0.15

    static func lines(from lines: [TextLine]) -> [String] {
        let code = lines.filter { !isNumberOnly($0) }
        let cell = characterWidth(in: code)
        let base = code.compactMap { $0.contentWords.first.map { Double($0.rect.minX) } }.min() ?? 0
        let indent = indentCell(of: code, base: base, glyphCell: cell)
        let numberWidth = lines.map { number(of: $0)?.count ?? 0 }.max() ?? 0
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
            output.append(
                render(line, base: base, cell: cell, indentCell: indent, numberWidth: numberWidth)
            )
            previous = line
        }
        return output
    }

    /// A blank line of a numbered listing, whose only word is its number.
    private static func isNumberOnly(_ line: TextLine) -> Bool {
        !line.isMonospace && line.lineNumber == nil && line.words.count == 1
            && TextLine.isPlainNumber(line.words[0])
    }

    /// Numbers that go back mean a new listing, such as the second of a pair set side by side.
    static func startsOver(_ line: TextLine, after lines: [TextLine]) -> Bool {
        guard let current = number(of: line).flatMap(Int.init),
            let previous = lines.last(where: { number(of: $0) != nil }).flatMap(number(of:))
                .flatMap(Int.init)
        else { return false }
        return current <= previous
    }

    private static func number(of line: TextLine) -> String? {
        line.lineNumber?.text ?? (isNumberOnly(line) ? line.words[0].text : nil)
    }

    /// Numbers are right-aligned in their own column, so indentation still reads as code does.
    private static func render(
        _ line: TextLine,
        base: Double,
        cell: Double,
        indentCell: Double,
        numberWidth: Int
    ) -> String {
        var text = ""
        if numberWidth > 0 {
            let number = number(of: line) ?? ""
            text += String(repeating: " ", count: numberWidth - number.count) + number
            if isNumberOnly(line) { return text }
            text += " "
        }
        let start = line.contentWords.first.map { Double($0.rect.minX) } ?? base
        text += String(repeating: " ", count: spaces(start - base, cell: indentCell))
        var previous: Word?
        for word in line.contentWords {
            if let previous, !word.isGlued {
                let gap = word.rect.minX - previous.rect.maxX
                text += String(repeating: " ", count: max(1, spaces(gap, cell: cell)))
            }
            text += TextNormalizer.normalize(word.text)
            previous = word
        }
        return text
    }

    /// The width of one space of indentation. LaTeX's `listings` sets leading spaces wider than
    /// its glyphs (measured: 4.83 against 4.62 at 8 pt), so measuring by glyphs drifts with depth,
    /// and a third level comes out at 13 spaces rather than 12. When every indent is a multiple
    /// of the smallest one, that's the code's real step, whatever its width.
    private static func indentCell(
        of lines: [TextLine],
        base: Double,
        glyphCell: Double
    ) -> Double {
        guard glyphCell > 0 else { return glyphCell }
        let indents = lines.compactMap { $0.contentWords.first.map { Double($0.rect.minX) - base } }
            .filter { $0 > glyphCell / 2 }
        guard let step = indents.min() else { return glyphCell }
        let isRegular = indents.allSatisfy { indent in
            abs(indent / step - (indent / step).rounded()) <= indentStepTolerance
        }
        let spacesPerStep = (step / glyphCell).rounded()
        return isRegular && spacesPerStep >= 1 ? step / spacesPerStep : glyphCell
    }

    private static func spaces(_ distance: Double, cell: Double) -> Int {
        guard cell > 0, distance > 0, distance.isFinite else { return 0 }
        return Int(min((distance / cell).rounded(), maximumSpaces))
    }

    private static func characterWidth(in lines: [TextLine]) -> Double {
        let widths = lines.flatMap(\.contentWords)
            .filter { !$0.text.isEmpty }
            .map { $0.rect.width / Double($0.text.count) }
            .sorted()
        return widths.isEmpty ? 0 : widths[widths.count / 2]
    }
}

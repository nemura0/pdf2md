import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct ExtractedText {
    var words: [Word] = []
    var matched = 0
    var unmatched = 0
}

/// Combines PDFKit's text and word rectangles with the content stream's font facts.
///
/// Text comes from `page.string` through `selection(for: NSRange)`, which stays aligned with it,
/// where PDFKit's per-character bounds drift after ligatures (measured: ADR-0003).
enum PDFTextExtractor {
    /// Words taller than this many font sizes span two lines, without whitespace between them.
    private static let maximumLineHeightRatio = 2.2
    /// A rotated word is drawn sideways, so most pages' stamps and axis labels leave the flow.
    /// If most words are rotated the page itself is, and its text has to stay.
    private static let rotatedPageShare = 0.5
    private static let syntheticLineHeight = 14.0
    private static let syntheticCharWidth = 6.0
    private static let syntheticMargin = 72.0
    private static let baselineDescentShare = 0.2

    static func extract(
        page: PDFPage,
        trace: PageTrace,
        geometry: DisplayGeometry
    ) -> ExtractedText {
        guard let string = page.string, !string.isEmpty else { return ExtractedText() }
        let index = RunIndex(runs: trace.runs)
        let text = string as NSString
        var result = ExtractedText()
        var rotated: [(token: NSRange, line: Int)] = []
        var lineNumber = 0

        forEachToken(in: text) { range, newlinesBefore in
            lineNumber += newlinesBefore
            guard let selection = page.selection(for: range) else { return }
            let rect = geometry.convert(selection.bounds(for: page))
            guard rect.width > 0, rect.height > 0 else { return }
            let bestRun = index.bestRun(for: rect)
            if let bestRun, !bestRun.isHorizontal {
                rotated.append((range, lineNumber))
            } else if rect.height > maximumLineHeightRatio * (bestRun?.size ?? rect.height) {
                appendSplitByLine(
                    selection,
                    page: page,
                    geometry: geometry,
                    index: index,
                    to: &result
                )
            } else {
                append(
                    token: text.substring(with: range),
                    range: range,
                    rect: rect,
                    selection: selection,
                    page: page,
                    geometry: geometry,
                    index: index,
                    to: &result
                )
            }
        }

        if !rotated.isEmpty,
            Double(rotated.count) > Double(rotated.count + result.words.count) * rotatedPageShare
        {
            result.words += syntheticWords(rotated, text: text)
        }
        return result
    }

    private static func forEachToken(in text: NSString, body: (NSRange, Int) -> Void) {
        let separators = CharacterSet.whitespacesAndNewlines
        let length = text.length
        var location = 0
        var newlines = 0
        while location < length {
            let character = text.character(at: location)
            guard let scalar = UnicodeScalar(character), separators.contains(scalar) else {
                var end = location
                while end < length {
                    if let scalar = UnicodeScalar(text.character(at: end)),
                        separators.contains(scalar)
                    {
                        break
                    }
                    end += 1
                }
                body(NSRange(location: location, length: end - location), newlines)
                newlines = 0
                location = end
                continue
            }
            if CharacterSet.newlines.contains(scalar) { newlines += 1 }
            location += 1
        }
    }

    private static func appendSplitByLine(
        _ selection: PDFSelection,
        page: PDFPage,
        geometry: DisplayGeometry,
        index: RunIndex,
        to result: inout ExtractedText
    ) {
        for line in selection.selectionsByLine() {
            guard let string = line.string, !string.isEmpty else { continue }
            let rect = geometry.convert(line.bounds(for: page))
            guard rect.width > 0, rect.height > 0 else { continue }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let run = index.bestRun(for: rect) {
                result.matched += 1
                result.words.append(word(trimmed, rect: rect, run: run, isGlued: false))
            } else {
                result.unmatched += 1
                result.words.append(fallbackWord(trimmed, rect: rect, selection: line))
            }
        }
    }

    private static func append(
        token: String,
        range: NSRange,
        rect: CGRect,
        selection: PDFSelection,
        page: PDFPage,
        geometry: DisplayGeometry,
        index: RunIndex,
        to result: inout ExtractedText
    ) {
        let runs = index.distinctRuns(overlapping: rect)
        guard let first = runs.first else {
            result.unmatched += 1
            result.words.append(fallbackWord(token, rect: rect, selection: selection))
            return
        }
        result.matched += 1
        if runs.count == 1 {
            result.words.append(
                word(token, rect: rect, run: index.bestRun(for: rect) ?? first, isGlued: false)
            )
            return
        }
        result.words += split(
            token: token,
            range: range,
            runs: runs,
            page: page,
            geometry: geometry
        )
    }

    /// Splits a word at a real font or baseline boundary, such as `x2`. Only here are characters
    /// measured one at a time, so ligatures can't make the rest of the page drift.
    private static func split(
        token: String,
        range: NSRange,
        runs: [TextRun],
        page: PDFPage,
        geometry: DisplayGeometry
    ) -> [Word] {
        let text = token as NSString
        var pieces: [(run: TextRun, text: String, rect: CGRect)] = []
        var location = 0
        while location < text.length {
            let composed = text.rangeOfComposedCharacterSequence(at: location)
            let absolute = NSRange(
                location: range.location + composed.location,
                length: composed.length
            )
            location = composed.upperBound
            guard let selection = page.selection(for: absolute) else { continue }
            let rect = geometry.convert(selection.bounds(for: page))
            let run = runs.last { $0.originX <= rect.midX } ?? runs[0]
            let piece = text.substring(with: composed)
            if let last = pieces.last, isSameStyle(last.run, run) {
                pieces[pieces.count - 1].text += piece
                pieces[pieces.count - 1].rect = last.rect.union(rect)
            } else {
                pieces.append((run, piece, rect))
            }
        }
        return pieces.enumerated().map { offset, piece in
            word(piece.text, rect: piece.rect, run: piece.run, isGlued: offset > 0)
        }
    }

    private static func isSameStyle(_ first: TextRun, _ second: TextRun) -> Bool {
        first.style == second.style && abs(first.size - second.size) < 0.1
            && abs(first.baseline - second.baseline) < 0.5
    }

    private static func word(_ text: String, rect: CGRect, run: TextRun, isGlued: Bool) -> Word {
        Word(
            text: text,
            rect: rect,
            baseline: run.baseline,
            size: run.size,
            font: run.style,
            isGlued: isGlued
        )
    }

    /// No matching show operation, as with Type3 fonts in unusual forms. `NSFont` isn't reliable
    /// for names (A5), but it beats nothing, and its sizes are right.
    private static func fallbackWord(_ token: String, rect: CGRect, selection: PDFSelection) -> Word
    {
        let attributed = selection.attributedString
        let font =
            attributed?.length ?? 0 > 0
            ? attributed?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
        let traits = font?.fontDescriptor.symbolicTraits
        return Word(
            text: token,
            rect: rect,
            baseline: rect.maxY - rect.height * baselineDescentShare,
            size: font.map { Double($0.pointSize) } ?? rect.height,
            font: FontStyle(
                name: font?.fontName ?? "",
                isBold: traits?.contains(.bold) ?? false,
                isItalic: traits?.contains(.italic) ?? false,
                isMonospace: traits?.contains(.monoSpace) ?? false
            )
        )
    }

    /// When the page is drawn sideways with no `/Rotate`, geometry is useless, so text keeps
    /// `page.string`'s order on a synthetic grid.
    private static func syntheticWords(
        _ tokens: [(token: NSRange, line: Int)],
        text: NSString
    ) -> [Word] {
        var words: [Word] = []
        var x = syntheticMargin
        var currentLine = -1
        for (range, line) in tokens {
            if line != currentLine {
                currentLine = line
                x = syntheticMargin
            }
            let token = text.substring(with: range)
            let width = Double(token.count) * syntheticCharWidth
            let y = syntheticMargin + Double(line) * syntheticLineHeight
            words.append(
                Word(
                    text: token,
                    rect: CGRect(x: x, y: y, width: width, height: syntheticLineHeight * 0.85),
                    baseline: y + syntheticLineHeight * 0.65,
                    size: syntheticCharWidth * 2,
                    font: FontStyle(name: "", isBold: false, isItalic: false, isMonospace: false)
                )
            )
            x += width + syntheticCharWidth
        }
        return words
    }
}

/// Runs sorted by baseline, so finding a word's run doesn't scan the page. Word processors can
/// emit one show operation per glyph.
struct RunIndex {
    /// From probes: run origins sit up to this far from PDFKit's word rect.
    private static let verticalTolerance = 2.0
    private static let horizontalTolerance = 1.5

    private let runs: [TextRun]
    private let baselines: [Double]

    init(runs: [TextRun]) {
        let sorted = runs.sorted { $0.baseline < $1.baseline }
        self.runs = sorted
        self.baselines = sorted.map(\.baseline)
    }

    private func candidates(for rect: CGRect) -> ArraySlice<TextRun> {
        let low = lowerBound(rect.minY - Self.verticalTolerance)
        let high = lowerBound(rect.maxY + Self.verticalTolerance + 0.001)
        return runs[low..<high]
    }

    private func lowerBound(_ value: Double) -> Int {
        var low = 0
        var high = baselines.count
        while low < high {
            let middle = (low + high) / 2
            if baselines[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// The show operation containing a word's start: the last one starting at or before it that
    /// hasn't ended yet. On a tie, the one closest to the rect's vertical middle.
    func bestRun(for rect: CGRect) -> TextRun? {
        var best: TextRun?
        for run in candidates(for: rect) {
            guard run.isHorizontal else {
                if rect.minY - Self.verticalTolerance <= run.baseline, best == nil,
                    abs(run.originX - rect.midX) < rect.width
                {
                    best = run
                }
                continue
            }
            guard run.originX <= rect.minX + Self.horizontalTolerance,
                !run.hasReliableEnd || run.endX >= rect.minX - Self.horizontalTolerance
            else { continue }
            if let current = best, current.isHorizontal {
                if run.originX > current.originX + 0.01 {
                    best = run
                } else if abs(run.originX - current.originX) <= 0.01,
                    abs(run.baseline - rect.midY) < abs(current.baseline - rect.midY)
                {
                    best = run
                }
            } else {
                best = run
            }
        }
        return best
    }

    /// Runs overlapping a word, one per distinct style, in x order. More than one means the word
    /// crosses a font or baseline boundary.
    func distinctRuns(overlapping rect: CGRect) -> [TextRun] {
        var overlapping = candidates(for: rect).filter { run in
            run.isHorizontal && run.originX < rect.maxX - Self.horizontalTolerance
                && (!run.hasReliableEnd || run.endX > rect.minX + Self.horizontalTolerance)
        }
        overlapping.sort { $0.originX < $1.originX }
        if overlapping.isEmpty, let best = bestRun(for: rect) { return [best] }
        var distinct: [TextRun] = []
        for run in overlapping {
            let isNew = !distinct.contains { other in
                other.style == run.style && abs(other.size - run.size) < 0.1
                    && abs(other.baseline - run.baseline) < 0.5
            }
            if isNew { distinct.append(run) }
        }
        return distinct
    }
}

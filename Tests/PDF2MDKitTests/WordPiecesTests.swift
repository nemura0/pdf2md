import CoreGraphics
import Foundation
import Testing

@testable import PDF2MDKit

/// What a listing's `...` measured in a real book: PDFKit reads `5...` as one word, and shares out
/// the gap between the line number and the dots among the characters around it. A synthetic PDF
/// drawn in the same order still reads as `5 ...`, so these tests hold the measured rects.
@Suite("Word pieces")
struct WordPiecesTests {
    private func run(_ start: Double, _ end: Double, size: Double, style: FontStyle) -> TextRun {
        TextRun(
            originX: start,
            endX: end,
            baseline: 100,
            size: size,
            style: style,
            isHorizontal: true,
            hasReliableEnd: true
        )
    }

    private var number: TextRun { run(26.39, 28.9, size: 4.98, style: .body) }
    private var dots: TextRun { run(72.8, 86.2, size: 7.97, style: .mono) }

    @Test("a character measured across a gap belongs to the run it reaches")
    func acrossGap() {
        let first = CGRect(x: 50.86, y: 90, width: 26.26, height: 10)
        let placed = PDFTextExtractor.place(first, among: [number, dots])
        #expect(placed.run.style == .mono)
        #expect(placed.rect.minX == 72.8)
        #expect(placed.rect.maxX == 77.12)
    }

    @Test("a line number measured across the gap stays in its own run, at its own width")
    func numberAcrossGap() {
        let digit = CGRect(x: 26.39, y: 90, width: 24.47, height: 10)
        let placed = PDFTextExtractor.place(digit, among: [number, dots])
        #expect(placed.run.style == .body)
        #expect(placed.rect.maxX == 28.9)
    }

    @Test("a character inside its run stays there")
    func insideItsRun() {
        let second = CGRect(x: 77.12, y: 90, width: 4.64, height: 10)
        #expect(PDFTextExtractor.place(second, among: [number, dots]).run.style == .mono)
    }

    @Test("runs that touch aren't a gap to share out, however narrow the character")
    func touchingRuns() {
        let first = run(40, 45, size: 5, style: .body)
        let second = run(44.8, 50, size: 5, style: .body)
        let dot = CGRect(x: 43.8, y: 90, width: 1.3, height: 10)
        #expect(PDFTextExtractor.place(dot, among: [first, second]).run.originX == 40)
    }

    /// Measured on a real book's `LuaTeX6.`, with a word's runs as they arrive: one per style. The
    /// `X` shares its style with `Lua`, so it has no run of its own and seems to be in a gap.
    @Test("a letter with no run of its own stays out of the script after it")
    func letterWithoutRun() {
        let lua = run(67.85, 78.4, size: 9.96, style: .body)
        var lowered = run(88.31, 94.26, size: 9.96, style: .body)
        lowered.baseline = 102.2
        let script = run(99.66, 103.36, size: 6.97, style: .body)
        let rect = CGRect(x: 93.64, y: 90, width: 6.02, height: 10)
        let placed = PDFTextExtractor.place(rect, among: [lua, lowered, script])
        #expect(placed.run.originX == lowered.originX)
    }

    @Test("a character that only touches the code after it stays out of it")
    func touchingCode() {
        let text = run(40, 45, size: 10, style: .body)
        let code = run(60, 70, size: 8, style: .mono)
        let rect = CGRect(x: 54, y: 90, width: 6, height: 10)
        #expect(PDFTextExtractor.place(rect, among: [text, code]).run.style == .body)
    }

    @Test("a line number and its code are two words, across a gutter")
    func apartAcrossGutter() {
        let apart = PDFTextExtractor.words(from: [
            WordPiece(
                run: number,
                text: "5",
                rect: CGRect(x: 26.39, y: 90, width: 2.5, height: 10)
            ),
            WordPiece(
                run: dots,
                text: "...",
                rect: CGRect(x: 72.8, y: 90, width: 13.4, height: 10)
            ),
        ])
        #expect(apart.map(\.isGlued) == [false, false])
    }

    /// Measured on a real book: `LaTeX`, `LuaTeX` and `10^-45` come apart if a gap is enough.
    @Test("any other gap inside a word leaves it whole")
    func gluedAcrossOtherGaps() {
        let body = run(40, 60, size: 10, style: .body)
        let script = run(64, 70, size: 7, style: .body)
        let mono = run(40, 60, size: 10, style: .mono)
        let scripted = PDFTextExtractor.words(from: [
            WordPiece(run: body, text: "LuaTE", rect: CGRect(x: 40, y: 90, width: 20, height: 10)),
            WordPiece(run: script, text: "X", rect: CGRect(x: 64, y: 90, width: 6, height: 10)),
        ])
        #expect(scripted.map(\.isGlued) == [false, true])
        let afterCode = PDFTextExtractor.words(from: [
            WordPiece(run: mono, text: "x", rect: CGRect(x: 40, y: 90, width: 20, height: 10)),
            WordPiece(run: script, text: "2", rect: CGRect(x: 64, y: 90, width: 6, height: 10)),
        ])
        #expect(afterCode.map(\.isGlued) == [false, true])
    }

    @Test("a number and the dots after it read as a numbered line of a listing")
    func elisionIsListing() throws {
        let words = PDFTextExtractor.words(from: [
            WordPiece(
                run: number,
                text: "5",
                rect: CGRect(x: 26.39, y: 90, width: 2.5, height: 10)
            ),
            WordPiece(
                run: dots,
                text: "...",
                rect: CGRect(x: 72.8, y: 90, width: 13.4, height: 10)
            ),
        ])
        let line = TextLine(words: words)
        #expect(line.lineNumber?.text == "5")
        #expect(line.isMonospace)
    }
}

import CoreGraphics
import Foundation
import Testing

@testable import PDF2MDKit

@Suite("TableHint")
struct TableHintTests {
    private let width = 612.0

    private func row(_ y: Double, _ cells: [(String, Double)]) -> [TextLine] {
        cells.map { line($0.0, x: $0.1, y: y) }
    }

    @Test("aligned rows of short cells suggest a table")
    func alignedRows() {
        let lines = (0..<4).flatMap { index in
            row(100 + Double(index) * 14, [("name\(index)", 72), ("12", 220), ("yes", 340)])
        }
        #expect(TableHint.suggestsTable(lines: lines, rules: [], pageWidth: width))
    }

    @Test("two columns of prose don't")
    func prose() {
        let filler = String(repeating: "long words ", count: 9)
        let lines = (0..<6).flatMap { index in
            row(100 + Double(index) * 14, [(filler, 72), (filler, 330)])
        }
        #expect(!TableHint.suggestsTable(lines: lines, rules: [], pageWidth: width))
    }

    @Test("a grid of rules suggests a table with or without text")
    func grid() {
        let horizontal = (0..<4).map {
            RuleSegment(
                startX: 72,
                startY: 100 + Double($0) * 20,
                endX: 400,
                endY: 100 + Double($0) * 20
            )
        }
        let vertical = [72.0, 200, 400].map {
            RuleSegment(startX: $0, startY: 100, endX: $0, endY: 160)
        }
        #expect(TableHint.suggestsTable(lines: [], rules: horizontal + vertical, pageWidth: width))
    }

    @Test("three overlapping rules are a booktabs table, and scattered underlines aren't")
    func booktabs() {
        let booktabs = [100.0, 120, 200].map {
            RuleSegment(startX: 72, startY: $0, endX: 400, endY: $0)
        }
        #expect(TableHint.suggestsTable(lines: [], rules: booktabs, pageWidth: width))

        let underlines = [
            RuleSegment(startX: 72, startY: 100, endX: 120, endY: 100),
            RuleSegment(startX: 200, startY: 300, endX: 250, endY: 300),
            RuleSegment(startX: 400, startY: 500, endX: 460, endY: 500),
        ]
        #expect(!TableHint.suggestsTable(lines: [], rules: underlines, pageWidth: width))
    }

    @Test("ordinary text doesn't")
    func text() {
        let lines = (0..<8).map { line("A plain line of running text", y: 100 + Double($0) * 14) }
        #expect(!TableHint.suggestsTable(lines: lines, rules: [], pageWidth: width))
    }
}

@Suite("TableGrid")
struct TableGridTests {
    private let page = CGSize(width: 100, height: 100)

    private func cell(
        _ text: String,
        row: Int,
        column: Int,
        rows: Int = 1,
        columns: Int = 1
    ) -> RecognizedCell {
        RecognizedCell(
            text: text,
            rect: CGRect(
                x: Double(column) * 0.5,
                y: Double(row) * 0.5,
                width: Double(columns) * 0.5,
                height: Double(rows) * 0.5
            ),
            rows: row...(row + rows - 1),
            columns: column...(column + columns - 1)
        )
    }

    private func table(_ cells: [RecognizedCell]) -> RecognizedTable {
        RecognizedTable(rect: CGRect(x: 0, y: 0, width: 1, height: 1), cells: cells)
    }

    @Test("without a text layer, cells keep the OCR text, escaped")
    func ocrText() {
        let rows = TableGrid.rows(
            for: table([
                cell("a*", row: 0, column: 0), cell("b", row: 0, column: 1),
                cell("c", row: 1, column: 0), cell("d", row: 1, column: 1),
            ]),
            pageSize: page,
            words: nil
        )
        #expect(rows == [["a\\*", "b"], ["c", "d"]])
    }

    @Test("with a text layer, text comes from the words in each cell, not from OCR")
    func textLayer() {
        let rows = TableGrid.rows(
            for: table([
                cell("WRONG", row: 0, column: 0), cell("WRONG", row: 0, column: 1),
                cell("WRONG", row: 1, column: 0), cell("WRONG", row: 1, column: 1),
            ]),
            pageSize: page,
            words: [
                word("one", x: 5, y: 20), word("two", x: 60, y: 20),
                word("three", x: 5, y: 70), word("four", x: 60, y: 70),
            ]
        )
        #expect(rows == [["one", "two"], ["three", "four"]])
    }

    @Test("a spanning cell fills its first position")
    func spans() {
        let rows = TableGrid.rows(
            for: table([
                cell("wide", row: 0, column: 0, columns: 2),
                cell("c", row: 1, column: 0), cell("d", row: 1, column: 1),
            ]),
            pageSize: page,
            words: nil
        )
        #expect(rows == [["wide", ""], ["c", "d"]])
    }

    @Test("one row or one column isn't a table")
    func tooSmall() {
        let oneRow = table([cell("a", row: 0, column: 0), cell("b", row: 0, column: 1)])
        #expect(TableGrid.rows(for: oneRow, pageSize: page, words: nil) == nil)
        let oneColumn = table([cell("a", row: 0, column: 0), cell("b", row: 1, column: 0)])
        #expect(TableGrid.rows(for: oneColumn, pageSize: page, words: nil) == nil)
    }

    @Test("impossible ranges from outside are rejected, not trusted")
    func badRanges() {
        let negative = RecognizedCell(
            text: "x",
            rect: CGRect(x: 0, y: 0, width: 1, height: 1),
            rows: -1...1,
            columns: 0...1
        )
        #expect(TableGrid.rows(for: table([negative]), pageSize: page, words: nil) == nil)
        let huge = RecognizedCell(
            text: "x",
            rect: CGRect(x: 0, y: 0, width: 1, height: 1),
            rows: 0...1_000_000,
            columns: 0...1_000_000
        )
        #expect(TableGrid.rows(for: table([huge]), pageSize: page, words: nil) == nil)
    }

    @Test("two spans starting at one position keep both texts")
    func sharedStart() {
        let rows = TableGrid.rows(
            for: table([
                cell("one", row: 0, column: 0), cell("two", row: 0, column: 0, columns: 2),
                cell("c", row: 1, column: 0), cell("d", row: 1, column: 1),
            ]),
            pageSize: page,
            words: nil
        )
        #expect(rows?[0][0] == "one two")
    }

    @Test("a mostly empty grid isn't a table")
    func mostlyEmpty() {
        let sparse = table([
            cell("a", row: 0, column: 0), cell("", row: 0, column: 1), cell("", row: 1, column: 0),
            cell("", row: 1, column: 1),
        ])
        #expect(TableGrid.rows(for: sparse, pageSize: page, words: nil) == nil)
    }
}

@Suite("RecognizedWords")
struct RecognizedWordsTests {
    private let page = CGSize(width: 1000, height: 1000)
    private let body = "a line of ordinary body text"

    /// A line whose characters are `unit` points wide on average.
    private func line(_ text: String, unit: Double, y: Double = 0.1) -> RecognizedLine {
        RecognizedLine(
            text: text,
            rect: CGRect(x: 0.1, y: y, width: unit * Double(text.count) / 1000, height: 0.012)
        )
    }

    private func size(of text: String, among lines: [RecognizedLine]) throws -> Double {
        let words = RecognizedWords.words(from: lines, pageSize: page)
        let first = try #require(text.split(separator: " ").first.map(String.init))
        return try #require(words.first { $0.text == first }).size
    }

    @Test("a line splits into words, in order, inside its box")
    func split() {
        let box = RecognizedLine(
            text: "two words",
            rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02)
        )
        let words = RecognizedWords.words(from: [box], pageSize: page)
        #expect(words.map(\.text) == ["two", "words"])
        #expect(words[0].rect.minX == 100)
        #expect(words[0].rect.maxX < words[1].rect.minX)
        #expect(words[1].rect.maxX <= 600.001)
    }

    @Test("lines of one style get one size, whatever their measured noise")
    func noise() throws {
        let lines = [
            line(body, unit: 4.8), line("another line of body text", unit: 5.2, y: 0.12),
        ]
        #expect(try size(of: body, among: lines) == size(of: "another", among: lines))
    }

    @Test("a heading measures larger than the text around it")
    func heading() throws {
        let lines = [line("Introduction", unit: 8.5), line(body, unit: 5, y: 0.2)]
        #expect(try size(of: "Introduction", among: lines) > size(of: body, among: lines))
    }

    @Test("a short narrow line keeps the size of the text around it")
    func shortLine() throws {
        let lines = [line(body, unit: 5), line("ill.", unit: 2.5, y: 0.12)]
        #expect(try size(of: "ill.", among: lines) == size(of: body, among: lines))
    }

    @Test("a sentence's tail, code and math don't become headings, however wide they measure")
    func notHeadings() throws {
        for text in ["hand.", "public int next() {", "return value;", "R= 2n-1"] {
            let lines = [line(body, unit: 5), line(text, unit: 8, y: 0.2)]
            #expect(try size(of: text, among: lines) == size(of: body, among: lines), "\(text)")
        }
    }

    @Test("an empty line gives no words")
    func empty() {
        let blank = RecognizedLine(text: "  ", rect: CGRect(x: 0, y: 0, width: 0.1, height: 0.1))
        #expect(RecognizedWords.words(from: [blank], pageSize: page).isEmpty)
    }
}

@Suite("FigureFilter")
struct FigureFilterTests {
    private let page = CGSize(width: 100, height: 100)

    @Test("page-sized images and repeats on one page are dropped")
    func kept() {
        let figures = [
            FigureCandidate(digest: "bg", rect: CGRect(x: 0, y: 0, width: 100, height: 100)),
            FigureCandidate(digest: "a", rect: CGRect(x: 10, y: 10, width: 30, height: 30)),
            FigureCandidate(digest: "a", rect: CGRect(x: 50, y: 50, width: 30, height: 30)),
            FigureCandidate(digest: "b", rect: CGRect(x: 10, y: 50, width: 30, height: 30)),
        ]
        #expect(FigureFilter.kept(figures, pageSize: page).map(\.digest) == ["a", "b"])
    }

    @Test("a scan's images are the page, also when the scan is cut in strips")
    func strips() {
        let strips = (0..<4).map { index in
            FigureCandidate(
                digest: "strip\(index)",
                rect: CGRect(x: 0, y: Double(index) * 25, width: 100, height: 25)
            )
        }
        #expect(FigureFilter.imageCoverage(strips, pageSize: page) == 1)
        #expect(FigureFilter.kept(strips, pageSize: page, isOCR: true).isEmpty)
        #expect(FigureFilter.kept(strips, pageSize: page, isOCR: false).count == 4)
    }

    @Test("coverage is the images' share of the page, clipped to it")
    func coverage() {
        let figures = [
            FigureCandidate(digest: "a", rect: CGRect(x: 50, y: 0, width: 100, height: 100))
        ]
        #expect(FigureFilter.imageCoverage(figures, pageSize: page) == 0.5)
        #expect(FigureFilter.imageCoverage([], pageSize: page) == 0)
    }
}

@Suite("TextLayerQuality")
struct TextLayerQualityTests {
    private let realText = String(repeating: "Real words on a page. ", count: 10)

    @Test("usable text passes, even over a full-page image")
    func good() {
        #expect(!TextLayerQuality.needsOCR(text: realText, pageImageCoverage: 0))
        #expect(!TextLayerQuality.needsOCR(text: realText, pageImageCoverage: 1))
    }

    @Test("an empty page needs OCR")
    func empty() {
        #expect(TextLayerQuality.needsOCR(text: " \n ", pageImageCoverage: 0))
    }

    @Test("garbled glyphs need OCR, and bullet glyphs from Symbol fonts don't count as garbled")
    func garbled() {
        let garbled = String(repeating: "\u{FFFD}", count: 80) + "abc"
        #expect(TextLayerQuality.needsOCR(text: garbled, pageImageCoverage: 0))
        let privateUse = String(repeating: "\u{E123}", count: 80)
        #expect(TextLayerQuality.needsOCR(text: privateUse, pageImageCoverage: 0))
        let bullets = "\u{F0B7} one item\n\u{F0B7} two items\n\u{F0B7} three items"
        #expect(!TextLayerQuality.needsOCR(text: bullets, pageImageCoverage: 0))
    }

    @Test("a stamp over a scanned page needs OCR, and a short slide over no image doesn't")
    func stamp() {
        #expect(TextLayerQuality.needsOCR(text: "CONFIDENTIAL", pageImageCoverage: 0.95))
        #expect(!TextLayerQuality.needsOCR(text: "A short slide", pageImageCoverage: 0))
    }
}

@Suite("ObjectPlacement")
struct ObjectPlacementTests {
    private func object(_ rect: CGRect, covers: Bool = true) -> PageObject {
        PageObject(rect: rect, blocks: [.paragraph("object")], coversText: covers)
    }

    @Test("text inside a covering object leaves the flow, and other text stays")
    func covered() {
        let lines = [line("before", y: 50), line("inside", y: 110), line("after", y: 200)]
        let table = object(CGRect(x: 60, y: 100, width: 300, height: 40))
        #expect(
            ObjectPlacement.removingCovered(lines, by: [table]).map(\.text) == ["before", "after"]
        )
        let figure = object(CGRect(x: 60, y: 100, width: 300, height: 40), covers: false)
        #expect(ObjectPlacement.removingCovered(lines, by: [figure]).count == 3)
    }

    @Test("an object goes between the lines around it")
    func between() {
        let lines = [line("above", y: 50), line("below", y: 200)]
        let table = object(CGRect(x: 60, y: 100, width: 300, height: 40))
        #expect(
            ObjectPlacement.segments(lines: lines, objects: [table]) == [
                .lines([lines[0]]), .object(table), .lines([lines[1]]),
            ]
        )
    }

    @Test("with nothing below it, an object goes last")
    func last() {
        let lines = [line("above", y: 50)]
        let table = object(CGRect(x: 60, y: 100, width: 300, height: 40))
        #expect(
            ObjectPlacement.segments(lines: lines, objects: [table]) == [
                .lines(lines), .object(table),
            ]
        )
    }

    @Test("in a column, it follows that column's lines, not a higher line in the next column")
    func column() {
        let left = [line("left top", x: 72, y: 50), line("left end", x: 72, y: 300)]
        let right = [line("right top", x: 330, y: 50)]
        let figure = object(CGRect(x: 72, y: 100, width: 200, height: 100))
        let segments = ObjectPlacement.segments(lines: left + right, objects: [figure])
        #expect(
            segments == [
                .lines([left[0]]), .object(figure), .lines([left[1], right[0]]),
            ]
        )
    }

    @Test("a large line stays when its object only covers labels")
    func labels() {
        var figure = object(CGRect(x: 60, y: 100, width: 300, height: 100))
        figure.largestCoveredSize = 11
        let lines = [line("axis label", y: 120), line("A heading", y: 160, size: 18)]
        #expect(
            ObjectPlacement.removingCovered(lines, by: [figure]).map(\.text) == ["A heading"]
        )
    }

    @Test("an object inside an earlier covering object is dropped, since it has the same words")
    func overlaps() {
        let table = object(CGRect(x: 0, y: 0, width: 100, height: 100))
        let inner = object(CGRect(x: 10, y: 10, width: 20, height: 20))
        let apart = object(CGRect(x: 200, y: 0, width: 20, height: 20))
        #expect(ObjectPlacement.removingOverlaps([table, inner, apart]) == [table, apart])
    }

    @Test("no objects leave one run of lines, and no lines leave just the objects")
    func empty() {
        let lines = [line("text", y: 50)]
        #expect(ObjectPlacement.segments(lines: lines, objects: []) == [.lines(lines)])
        #expect(ObjectPlacement.segments(lines: [], objects: []).isEmpty)
        let table = object(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(ObjectPlacement.segments(lines: [], objects: [table]) == [.object(table)])
    }
}

@Suite("PageRecognition")
struct PageRecognitionTests {
    private let page = PageRecord(
        index: 0,
        width: 100,
        height: 100,
        words: [word("layer", x: 5, y: 20)],
        matchedWords: 1
    )
    private let recognized = RecognizedPage(
        lines: [
            RecognizedLine(text: "seen", rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1))
        ],
        tables: []
    )

    @Test("OCR replaces the words and marks the page")
    func ocr() {
        let result = PageRecognition.applying(recognized, to: page, needsOCR: true)
        #expect(result.words.map(\.text) == ["seen"])
        #expect(result.isOCR)
        #expect(result.matchedWords == 0)
    }

    @Test("a table pass keeps the text layer")
    func tablesOnly() {
        let result = PageRecognition.applying(recognized, to: page, needsOCR: false)
        #expect(result.words.map(\.text) == ["layer"])
        #expect(!result.isOCR)
    }

    @Test("when OCR finds nothing, a text layer stays, as with a stamp over a blank scan")
    func emptyOCR() {
        let empty = RecognizedPage(lines: [], tables: [])
        let result = PageRecognition.applying(empty, to: page, needsOCR: true)
        #expect(result.words.map(\.text) == ["layer"])
        #expect(!result.isOCR)
    }

    @Test("failed OCR fails the page, and a failed table pass doesn't")
    func failure() {
        #expect(PageRecognition.applying(nil, to: page, needsOCR: true).didFail)
        #expect(!PageRecognition.applying(nil, to: page, needsOCR: false).didFail)
    }

    @Test("the mode decides OCR, and a page with no words has no table to fill")
    func plan() {
        let blank = PageRecord(index: 0, width: 200, height: 100)
        let never = PageRecognition.plan(for: blank, rules: [], figures: [], mode: .never)
        #expect(never == .init(needsOCR: false, needsTables: false))
        let auto = PageRecognition.plan(for: blank, rules: [], figures: [], mode: .auto)
        #expect(auto.needsOCR)
        let always = PageRecognition.plan(for: page, rules: [], figures: [], mode: .always)
        #expect(always.needsOCR)
    }

    @Test("landscape pages with text always get a table pass")
    func slide() {
        var slide = page
        slide.width = 200
        let plan = PageRecognition.plan(for: slide, rules: [], figures: [], mode: .auto)
        #expect(plan.needsTables)
    }
}

@Suite("FigureNamer")
struct FigureNamerTests {
    private func figure(_ digest: String, crop: String? = nil) -> FigureCandidate {
        FigureCandidate(
            digest: digest,
            rect: CGRect(x: 0, y: 0, width: 50, height: 50),
            cropFile: crop ?? "\(digest).png"
        )
    }

    private func namer(repeated: Set<String> = [], assets: String? = "a b_assets") -> FigureNamer {
        FigureNamer(
            repeatedDigests: repeated,
            cropDirectory: URL(fileURLWithPath: "/crops"),
            assetsName: assets
        )
    }

    @Test("names follow the page and the order on it")
    func names() {
        var namer = namer()
        #expect(namer.link(for: figure("a"), pageIndex: 11) == "a b_assets/p0012-01.png")
        #expect(namer.link(for: figure("b"), pageIndex: 11) == "a b_assets/p0012-02.png")
        #expect(
            namer.link(for: figure("c", crop: "c.jpg"), pageIndex: 12) == "a b_assets/p0013-01.jpg"
        )
        #expect(namer.images.map(\.name) == ["p0012-01.png", "p0012-02.png", "p0013-01.jpg"])
        #expect(namer.images[0].source.path == "/crops/a.png")
    }

    @Test("an identical image links to its first copy, and only one file is kept")
    func duplicates() {
        var namer = namer()
        let first = namer.link(for: figure("a"), pageIndex: 0)
        let second = namer.link(for: figure("a"), pageIndex: 7)
        #expect(first == second)
        #expect(namer.images.count == 1)
    }

    @Test("repeated images, missing crops and --no-images give no link")
    func dropped() {
        var repeated = namer(repeated: ["logo"])
        #expect(repeated.link(for: figure("logo"), pageIndex: 0) == nil)
        var missing = namer()
        var noCrop = figure("a")
        noCrop.cropFile = nil
        #expect(missing.link(for: noCrop, pageIndex: 0) == nil)
        var disabled = namer(assets: nil)
        #expect(disabled.link(for: figure("a"), pageIndex: 0) == nil)
        #expect(repeated.images.isEmpty && missing.images.isEmpty && disabled.images.isEmpty)
    }
}

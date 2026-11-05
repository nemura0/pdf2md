import CoreGraphics
import Testing

@testable import PDF2MDKit

@Suite("Ruled tables")
struct RuledTableTests {
    /// A full grid: a horizontal rule at each `ys`, a vertical one at each `xs`, cut per row the
    /// way LaTeX's `tabular` draws them, with a small gap at every crossing.
    private func grid(xs: [Double], ys: [Double]) -> [RuleSegment] {
        let gap = 0.2
        var rules = ys.map {
            RuleSegment(startX: xs[0], startY: $0, endX: xs[xs.count - 1], endY: $0)
        }
        for (top, bottom) in zip(ys, ys.dropFirst()) {
            rules += xs.map {
                RuleSegment(startX: $0, startY: bottom - gap, endX: $0, endY: top + gap)
            }
        }
        return rules
    }

    @Test("a grid of rules gives rows of text, whatever Vision would see")
    func simpleGrid() throws {
        let rules = grid(xs: [40, 100, 200, 300], ys: [50, 62, 74])
        let page =
            words("Nombre", x: 45, y: 59, font: .bold) + words("Tamano", x: 105, y: 59, font: .bold)
            + words("Valor", x: 205, y: 59, font: .bold)
            + words("byte", x: 45, y: 71, font: .mono) + words("1 byte", x: 105, y: 71)
            + words("-128", x: 205, y: 71)
            + words("Texto fuera", x: 45, y: 90)
        let tables = RuledTables.find(rules: rules, words: page)
        let table = try #require(tables.first)
        #expect(tables.count == 1)
        #expect(
            table.rows == [
                ["Nombre", "Tamano", "Valor"],
                ["byte", "1 byte", "-128"],
            ]
        )
        #expect(table.rect.minY == 50)
        #expect(table.rect.maxX == 300)
    }

    @Test("a cell's lines are one text, with a word broken at the line end made whole")
    func wrappedCell() throws {
        let rules = grid(xs: [40, 100, 300], ys: [50, 62, 100])
        let page =
            words("A", x: 45, y: 59) + words("B", x: 105, y: 59)
            + words("float", x: 45, y: 71)
            + words("Almacena valores preci-", x: 105, y: 71)
            + words("sos y grandes", x: 105, y: 83)
            + words("Por ello no", x: 105, y: 95)
        let table = try #require(RuledTables.find(rules: rules, words: page).first)
        #expect(table.rows[1] == ["float", "Almacena valores precisos y grandes Por ello no"])
    }

    /// A grid whose column lines are cut at each line of text, with no rule across inside `body`.
    /// LaTeX draws a `tabular` this way when only the header has a line under it.
    private func gridWithLooseRows(
        xs: [Double],
        top: Double,
        header: Double,
        lines: [Double]
    ) -> [RuleSegment] {
        let bottom = lines[lines.count - 1]
        var rules = [top, header, bottom].map {
            RuleSegment(startX: xs[0], startY: $0, endX: xs[xs.count - 1], endY: $0)
        }
        let cuts = [top, header] + lines
        for (upper, lower) in zip(cuts, cuts.dropFirst()) {
            rules += xs.map {
                RuleSegment(startX: $0, startY: lower - 0.2, endX: $0, endY: upper + 0.2)
            }
        }
        return rules
    }

    @Test("rows with no rule between them are still rows, when every column's lines line up")
    func looseRows() throws {
        let rules = gridWithLooseRows(xs: [40, 100, 300], top: 50, header: 62, lines: [74, 86])
        let page =
            words("Nombre", x: 45, y: 59) + words("Descripcion", x: 105, y: 59)
            + words("boolean", x: 45, y: 71) + words("Dos valores", x: 105, y: 71)
            + words("char", x: 45, y: 83) + words("Una letra", x: 105, y: 83)
        let table = try #require(RuledTables.find(rules: rules, words: page).first)
        #expect(
            table.rows == [
                ["Nombre", "Descripcion"],
                ["boolean", "Dos valores"],
                ["char", "Una letra"],
            ]
        )
    }

    @Test("a wrapped cell in a row next to a short one stays in one row")
    func wrappedInLooseRow() throws {
        let rules = gridWithLooseRows(xs: [40, 100, 300], top: 50, header: 62, lines: [74, 86])
        let page =
            words("Nombre", x: 45, y: 59) + words("Descripcion", x: 105, y: 59)
            + words("float", x: 45, y: 71) + words("Una descripcion", x: 105, y: 71)
            + words("bastante larga", x: 105, y: 83)
        let table = try #require(RuledTables.find(rules: rules, words: page).first)
        #expect(table.rows[1] == ["float", "Una descripcion bastante larga"])
        #expect(table.rows.count == 2)
    }

    @Test("a word whose box reaches the row above still lands in its own row")
    func tallWordBoxes() throws {
        let rules = grid(xs: [40, 100, 300], ys: [50, 62, 74])
        let tall = { (text: String, x: Double, y: Double) in
            Word(
                text: text,
                rect: CGRect(x: x, y: y - 16, width: 30, height: 20),
                baseline: y,
                size: 10,
                font: .body
            )
        }
        let page = [tall("A", 45, 59), tall("B", 105, 59), tall("C", 45, 71), tall("D", 105, 71)]
        let table = try #require(RuledTables.find(rules: rules, words: page).first)
        #expect(table.rows == [["A", "B"], ["C", "D"]])
    }

    @Test("each grid on a page is its own table")
    func twoTables() {
        let rules =
            grid(xs: [40, 100, 200], ys: [50, 62, 74])
            + grid(xs: [40, 90, 300], ys: [90, 102, 114])
        let page =
            words("A", x: 45, y: 59) + words("B", x: 105, y: 59)
            + words("C", x: 45, y: 71) + words("D", x: 105, y: 71)
            + words("E", x: 45, y: 99) + words("F", x: 95, y: 99)
            + words("G", x: 45, y: 111) + words("H", x: 95, y: 111)
        #expect(RuledTables.find(rules: rules, words: page).count == 2)
    }

    @Test("a box in a class diagram has one column, so it isn't a table")
    func classBox() {
        let rules = grid(xs: [155, 315], ys: [200, 218, 258, 308])
        let page =
            words("Persona", x: 200, y: 211) + words("-rut: String", x: 160, y: 229)
            + words("+getRut():String", x: 160, y: 280)
        #expect(RuledTables.find(rules: rules, words: page).isEmpty)
    }

    @Test("rules with no frame around them aren't a table")
    func noFrame() {
        let rules = [
            RuleSegment(startX: 40, startY: 50, endX: 200, endY: 50),
            RuleSegment(startX: 40, startY: 62, endX: 200, endY: 62),
            RuleSegment(startX: 40, startY: 74, endX: 120, endY: 74),
            RuleSegment(startX: 100, startY: 50, endX: 100, endY: 74),
            RuleSegment(startX: 40, startY: 50, endX: 40, endY: 74),
        ]
        let page =
            words("A", x: 45, y: 59) + words("B", x: 105, y: 59)
            + words("C", x: 45, y: 71) + words("D", x: 105, y: 71)
        #expect(RuledTables.find(rules: rules, words: page).isEmpty)
    }

    /// Two class boxes side by side, nearly touching, so their edges cover most of a frame.
    @Test("two boxes in a diagram, joined by an arrow, aren't a table")
    func twoBoxes() {
        let box = { (left: Double, right: Double) in
            [50.0, 62, 74, 86].map {
                RuleSegment(startX: left, startY: $0, endX: right, endY: $0)
            } + [left, right].map { RuleSegment(startX: $0, startY: 50, endX: $0, endY: 86) }
        }
        let arrow = RuleSegment(startX: 120, startY: 68, endX: 136, endY: 68)
        let page =
            words("App", x: 45, y: 59) + words("Sistema", x: 145, y: 59)
            + words("sistema", x: 45, y: 71) + words("nombres", x: 145, y: 71)
            + words("main", x: 45, y: 83) + words("leer", x: 145, y: 83)
        let rules = box(40, 120) + box(136, 300) + [arrow]
        #expect(RuledTables.find(rules: rules, words: page).isEmpty)
    }

    @Test("a column with no text at all isn't a column, so this is a drawing")
    func emptyColumn() {
        let rules = grid(xs: [40, 100, 200], ys: [50, 62, 74, 86])
        let page =
            words("Viaje", x: 45, y: 59) + words("fecha", x: 45, y: 71)
            + words("hora", x: 45, y: 83)
        #expect(RuledTables.find(rules: rules, words: page).isEmpty)
    }

    @Test("an array drawn with its indices above and empty cells is a drawing")
    func drawnArray() {
        let rules = grid(xs: [40, 60, 80, 100], ys: [50, 62, 70])
        let page =
            words("[0]", x: 42, y: 59) + words("[1]", x: 62, y: 59) + words("[2]", x: 82, y: 59)
        #expect(RuledTables.find(rules: rules, words: page).isEmpty)
    }

    @Test("a grid that's mostly empty is a drawing")
    func emptyGrid() {
        let rules = grid(xs: [40, 100, 160, 220], ys: [50, 62, 74, 86])
        #expect(RuledTables.find(rules: rules, words: words("A", x: 45, y: 59)).isEmpty)
    }

    @Test("a double rule makes no empty row")
    func doubleRule() throws {
        let rules = grid(xs: [40, 100, 200], ys: [50, 62, 64, 76])
        let page =
            words("A", x: 45, y: 59) + words("B", x: 105, y: 59)
            + words("C", x: 45, y: 73) + words("D", x: 105, y: 73)
        let table = try #require(RuledTables.find(rules: rules, words: page).first)
        #expect(table.rows == [["A", "B"], ["C", "D"]])
    }

    @Test("a cell spanning two columns keeps its words together, in its first position")
    func spanningCell() throws {
        let inner = 100.0
        let rules =
            grid(xs: [40, inner, 200], ys: [50, 62, 74]).filter { rule in
                // No column line in the first row.
                !(rule.isVertical && rule.startX == inner && rule.endY < 60)
            }
        let page =
            words("Titulo de la tabla", x: 60, y: 59)
            + words("C", x: 45, y: 71) + words("D", x: 105, y: 71)
        let table = try #require(RuledTables.find(rules: rules, words: page).first)
        #expect(table.rows == [["Titulo de la tabla", ""], ["C", "D"]])
    }

    @Test("a page with far too many rules is left alone")
    func tooManyRules() {
        let rules = (0..<5000).map {
            RuleSegment(startX: 0, startY: Double($0), endX: 100, endY: Double($0))
        }
        #expect(RuledTables.find(rules: rules, words: words("A", x: 5, y: 5)).isEmpty)
    }
}

@Suite("Symbol glyphs")
struct SymbolGlyphTests {
    private func run(codes: [Int], x: Double, y: Double = 100, font: String = "bbding") -> TextRun {
        TextRun(
            originX: x,
            endX: x + 10,
            baseline: y,
            size: 10,
            style: FontStyle(name: font, isBold: false, isItalic: false, isMonospace: false),
            isHorizontal: true,
            hasReliableEnd: true,
            symbolCodes: codes
        )
    }

    /// Each run is compared with every word on the page, so a hostile page could run for minutes.
    @Test("a page's symbol runs are limited")
    func limitedRuns() {
        let runs = (0..<3000).map { run(codes: [34], x: Double($0) * 10) }
        #expect(SymbolGlyphs.words(runs: runs, text: []).count == 2000)
    }

    @Test("a check mark with no text becomes a word where it was drawn")
    func checkMark() throws {
        let found = SymbolGlyphs.words(runs: [run(codes: [34], x: 140)], text: [])
        let symbol = try #require(found.first)
        #expect(symbol.text == "✔")
        #expect(symbol.rect.minX == 140 && symbol.baseline == 100)
    }

    @Test("a symbol nothing is known about still leaves a mark")
    func unknownSymbol() {
        let found = SymbolGlyphs.words(runs: [run(codes: [7], x: 140, font: "wasy10")], text: [])
        #expect(found.map(\.text) == ["■"])
    }

    @Test("a run from a font with text, or a blank, adds nothing")
    func ordinaryRuns() {
        #expect(SymbolGlyphs.words(runs: [run(codes: [], x: 140)], text: []).isEmpty)
        #expect(SymbolGlyphs.words(runs: [run(codes: [32], x: 140)], text: []).isEmpty)
    }

    @Test("a symbol PDFKit did read isn't added twice")
    func alreadyRead() {
        let text = [word("✔", x: 141, y: 100)]
        #expect(SymbolGlyphs.words(runs: [run(codes: [34], x: 140)], text: text).isEmpty)
    }

    @Test("a character PDFKit measured across the check marks beside it stays in its own run")
    func swallowedGlyphs() {
        let mono = TextRun(
            originX: 40,
            endX: 72.5,
            baseline: 100,
            size: 10,
            style: .mono,
            isHorizontal: true,
            hasReliableEnd: true
        )
        let wide = CGRect(x: 66.5, y: 90, width: 360, height: 13)
        let placed = PDFTextExtractor.place(wide, among: [mono, run(codes: [34], x: 140)])
        #expect(placed.run.style == .mono)
        #expect(placed.rect.maxX == 72.5)
    }
}

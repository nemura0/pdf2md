import CoreGraphics
import Foundation
import Testing

@testable import PDF2MDKit

@Suite("Footnotes")
struct FootnoteTests {
    private let pageSize = CGSize(width: 480, height: 680)
    private let rule = RuleSegment(startX: 40, startY: 580, endX: 200, endY: 580)

    /// A superscript marker, the way the extractor splits it from the word beside it.
    private func marker(_ text: String, x: Double, y: Double, size: Double = 6) -> Word {
        word(text, x: x, y: y - 2.8, size: size, isGlued: true)
    }

    private func bodyLine(_ text: String, y: Double, marker mark: String? = nil) -> TextLine {
        var all = words(text, x: 40, y: y)
        if let mark, let last = all.last {
            all.append(marker(mark, x: last.rect.maxX, y: y))
        }
        return TextLine(words: all)
    }

    private func noteLine(_ mark: String?, _ text: String, x: Double = 40, y: Double) -> TextLine {
        let start = mark == nil ? x : x + 4
        let head = mark.map { [word($0, x: x, y: y - 2.8, size: 6)] } ?? []
        var rest = words(text, x: start, y: y, size: 8)
        if mark != nil, !rest.isEmpty {
            rest[0].isGlued = true
        }
        return TextLine(words: head + rest)
    }

    private func separate(
        _ lines: [TextLine],
        rules: [RuleSegment]? = nil,
        blockers: [CGRect] = []
    ) -> FootnotePage {
        Footnotes.separate(
            lines: lines,
            rules: rules ?? [rule],
            blockers: blockers,
            pageIndex: 21,
            bodySize: 10,
            pageSize: pageSize
        )
    }

    @Test("a note leaves the text, and its marker becomes a reference to it")
    func oneNote() throws {
        let page = separate([
            bodyLine("Un entorno de desarrollo", y: 300, marker: "6"),
            bodyLine("y luego sigue la frase.", y: 312),
            noteLine("6", "IDE: entorno integrado", y: 600),
        ])
        #expect(page.lines.count == 2)
        #expect(page.notes == [.footnote(label: "p22-6", text: "IDE: entorno integrado")])
        let rendered = InlineRenderer.render(line: page.lines[0])
        #expect(rendered == "Un entorno de desarrollo[^p22-6]")
    }

    @Test("punctuation set small along with the marker stays after the reference")
    func markerWithPunctuation() {
        let page = separate([
            bodyLine("Se instala el JRE", y: 300, marker: "3."),
            noteLine("3", "Java Runtime Environment", y: 600),
        ])
        #expect(page.notes == [.footnote(label: "p22-3", text: "Java Runtime Environment")])
        #expect(InlineRenderer.render(line: page.lines[0]) == "Se instala el JRE[^p22-3].")
    }

    @Test("a listing's gutter further left than the text doesn't hide the rule")
    func gutterLeftOfText() {
        let gutter = TextLine(
            words: [word("1", x: 25, y: 200, size: 5)]
                + words("int x;", x: 40, y: 200, size: 8, font: .mono)
        )
        let page = separate([
            gutter,
            bodyLine("Texto", y: 300, marker: "1"),
            noteLine("1", "Una nota", y: 600),
        ])
        #expect(page.notes == [.footnote(label: "p22-1", text: "Una nota")])
    }

    @Test("a note runs over several lines, and a word broken at the line's end is made whole")
    func continuedNote() {
        let page = separate([
            bodyLine("Texto", y: 300, marker: "1"),
            noteLine("1", "Una nota bastante lar-", y: 600),
            noteLine(nil, "ga que sigue", y: 610),
        ])
        #expect(
            page.notes == [.footnote(label: "p22-1", text: "Una nota bastante larga que sigue")]
        )
    }

    @Test("several notes can share one line")
    func notesOnOneLine() {
        var line = noteLine("5", "Primera nota", y: 600).words
        let end = line.last?.rect.maxX ?? 0
        line += [word("6", x: end + 8, y: 597.2, size: 6)]
        line += words("Segunda", x: end + 12, y: 600, size: 8).map { word in
            var glued = word
            glued.isGlued = true
            return glued
        }
        let page = separate([
            bodyLine("Uno", y: 300, marker: "5"),
            bodyLine("Dos", y: 312, marker: "6"),
            TextLine(words: line),
        ])
        #expect(
            page.notes == [
                .footnote(label: "p22-5", text: "Primera nota"),
                .footnote(label: "p22-6", text: "Segunda"),
            ]
        )
    }

    @Test("a URL in a note keeps its text")
    func urlNote() {
        var url = word("https://www.tiobe.com/", x: 44, y: 600, size: 8, font: .mono)
        url.isGlued = true
        let page = separate([
            bodyLine("Ver indice", y: 300, marker: "2"),
            TextLine(words: [word("2", x: 40, y: 597.2, size: 6), url]),
        ])
        #expect(page.notes == [.footnote(label: "p22-2", text: "https://www.tiobe.com/")])
    }

    @Test("a note with nothing pointing at it stays readable as text")
    func unreferencedNote() {
        let page = separate([
            bodyLine("Texto sin marca", y: 300),
            noteLine("3", "Una nota huerfana", y: 600),
        ])
        #expect(page.notes == [.footnote(label: nil, text: "\\[3\\] Una nota huerfana")])
    }

    @Test("a marker no label can hold still gets a label")
    func symbolMarker() {
        let page = separate([
            bodyLine("Texto", y: 300, marker: "*"),
            noteLine("*", "Con un asterisco", y: 600),
        ])
        #expect(page.notes == [.footnote(label: "p22-1", text: "Con un asterisco")])
    }

    @Test("a rule with ordinary text below it isn't a footnote rule")
    func bodySizeBelow() {
        let lines = [
            bodyLine("Texto", y: 300),
            TextLine(words: words("Mas texto normal", x: 40, y: 600)),
        ]
        let page = separate(lines)
        #expect(page.lines == lines)
        #expect(page.notes.isEmpty)
    }

    @Test("small print with no marker isn't a note")
    func noMarker() {
        let lines = [
            bodyLine("Texto", y: 300),
            TextLine(words: words("Fuente: elaboracion propia", x: 40, y: 600, size: 8)),
        ]
        #expect(separate(lines).notes.isEmpty)
    }

    @Test("a rule inside a drawing or a table isn't a footnote rule")
    func ruleInsideDrawing() {
        let lines = [
            bodyLine("Texto", y: 300, marker: "1"),
            noteLine("1", "Una etiqueta", y: 600),
        ]
        let page = separate(lines, blockers: [CGRect(x: 30, y: 570, width: 300, height: 60)])
        #expect(page.notes.isEmpty)
    }

    @Test("a rule across the whole text, or high on the page, isn't a footnote rule")
    func otherRules() {
        let lines = [
            bodyLine("Texto", y: 100, marker: "1"),
            bodyLine(
                "Una linea bien larga de texto normal que llega hasta el margen derecho",
                y: 112
            ),
            noteLine("1", "Una nota", y: 600),
        ]
        let wide = RuleSegment(startX: 40, startY: 580, endX: 440, endY: 580)
        let high = RuleSegment(startX: 40, startY: 80, endX: 200, endY: 80)
        #expect(separate(lines, rules: [wide]).notes.isEmpty)
        #expect(separate(lines, rules: [high]).notes.isEmpty)
    }

    @Test("a page number below the notes stays where it is")
    func pageNumberBelow() {
        let number = TextLine(words: words("10", x: 40, y: 650))
        let page = separate([
            bodyLine("Texto", y: 300, marker: "1"),
            noteLine("1", "Una nota", y: 600),
            number,
        ])
        #expect(page.notes == [.footnote(label: "p22-1", text: "Una nota")])
        #expect(page.lines.last == number)
    }
}

@Suite("Page flow with footnotes")
struct FootnoteFlowTests {
    private func output(_ pages: [(blocks: [Block], marker: String)]) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        var flow = PageFlow()
        var stream = try MarkdownStream(url: url)
        for page in pages {
            try flow.write(page.blocks, pageMarker: page.marker, to: &stream)
        }
        try flow.finish(to: &stream)
        try stream.close()
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("a paragraph crossing a page isn't cut by the first page's notes")
    func paragraphCrossesNotes() throws {
        let text = try output([
            (
                [.paragraph("Una frase que sigue"), .footnote(label: "p1-1", text: "Nota uno")],
                "<!-- page 1 -->"
            ),
            ([.paragraph("en la otra pagina."), .paragraph("Otra.")], "<!-- page 2 -->"),
        ])
        #expect(
            text.hasSuffix(
                """
                Una frase que sigue en la otra pagina.

                [^p1-1]: Nota uno

                <!-- page 2 -->

                Otra.

                """
            )
        )
    }

    @Test("a note follows the text it belongs to, and comes before the next page's marker")
    func noteBeforeMarker() throws {
        let text = try output([
            (
                [.paragraph("Punto final."), .footnote(label: "p1-1", text: "Nota")],
                "<!-- page 1 -->"
            ),
            ([.paragraph("Nueva pagina.")], "<!-- page 2 -->"),
        ])
        let note = try #require(text.range(of: "[^p1-1]: Nota"))
        let marker = try #require(text.range(of: "<!-- page 2 -->"))
        let sentence = try #require(text.range(of: "Punto final."))
        #expect(sentence.upperBound <= note.lowerBound && note.upperBound <= marker.lowerBound)
    }
}

import Testing

@testable import PDF2MDKit

/// Lettered items and code that belongs to the sentence around it, as a real book sets them.
@Suite("BlockBuilder, lettered lists and code in sentences")
struct ListsAndSentenceCodeTests {
    private func blocks(_ lines: [TextLine]) -> [Block] {
        let profile = DocumentProfile(
            pageCount: 1,
            bodySize: 10,
            headingBands: [],
            title: DocumentTitle(text: "T", lineTexts: []),
            repeatedMarginKeys: [],
            repeatedImageDigests: [],
            isSlideDeck: false
        )
        return BlockBuilder(profile: profile).blocks(from: lines, isSlidePage: false)
    }

    @Test(
        "a marker counts as lettered only if it has a letter",
        arguments: [
            ("a)", true), ("(b)", true), ("c.", true), ("iv)", true),
            ("1.", false), ("(2)", false), ("•", false), ("word", false),
        ]
    )
    func lettered(token: String, isLettered: Bool) {
        #expect(ListMarker.isLettered(token) == isLettered)
    }

    @Test(
        "markers keep their Markdown form",
        arguments: [
            ("1.", "1."), ("12)", "12."), ("(3)", "3."), ("a)", "-"), ("(b)", "-"), ("c.", "-"),
            ("iv)", "-"), ("(viii)", "-"), ("•", "-"), ("-", "-"),
        ]
    )
    func markers(token: String, marker: String) {
        #expect(ListMarker.marker(forToken: token) == marker)
    }

    @Test(
        "a word isn't a marker",
        arguments: ["word", "12", "a", "(3", "palabra.", "ab)", "1234."]
    )
    func notMarkers(token: String) {
        #expect(ListMarker.marker(forToken: token) == nil)
    }

    private let italic = FontStyle(
        name: "LMSans10-Oblique",
        isBold: false,
        isItalic: true,
        isMonospace: false
    )

    /// An italic letter and an upright parenthesis, which PDFKit reads as two words.
    private func lettered(_ letter: String, _ text: String, y: Double, isGlued: Bool = true)
        -> TextLine
    {
        TextLine(
            words: [
                word(letter, x: 60, y: y, font: italic),
                word(")", x: 65, y: y, isGlued: isGlued),
            ] + words(text, x: 74, y: y)
        )
    }

    private func items(in blocks: [Block]) throws -> [ListItem] {
        guard blocks.count == 1, case .list(let items) = blocks[0] else {
            Issue.record("expected one list, got \(blocks)")
            return []
        }
        return items
    }

    @Test("lettered items are one list each, and keep the letter the text cites them by")
    func letteredItems() throws {
        let found = try items(
            in: blocks([
                lettered("d", "Compara el valor", y: 100),
                lettered("e", "Si es mayor entonces asigna", y: 112),
                lettered("f", "Si es menor entonces asigna", y: 124, isGlued: false),
            ])
        )
        #expect(found.map(\.marker) == ["-", "-", "-"])
        #expect(
            found.map(\.text) == [
                "d) Compara el valor",
                "e) Si es mayor entonces asigna",
                "f) Si es menor entonces asigna",
            ]
        )
    }

    @Test("a letter set in one word with its parenthesis keeps the letter too")
    func letterInOneWord() throws {
        let line = TextLine(
            words: [word("a)", x: 60, y: 100)] + words("Asigna algo", x: 74, y: 100)
        )
        #expect(try items(in: blocks([line])).map(\.text) == ["a) Asigna algo"])
    }

    @Test("a lettered item's next line goes on with it")
    func letteredContinues() throws {
        let found = try items(
            in: blocks([
                lettered("a", "El nombre del integrante", y: 100),
                line("que se encuentra ocupado.", x: 74, y: 112),
            ])
        )
        #expect(found.map(\.text) == ["a) El nombre del integrante que se encuentra ocupado."])
    }

    @Test("a word and a parenthesis opening a line aren't an item unless the word is one letter")
    func notLettered() {
        let line = TextLine(
            words: [word("valor", x: 60, y: 100), word(")", x: 85, y: 100, isGlued: true)]
                + words("y algo mas", x: 94, y: 100)
        )
        #expect(blocks([line]) == [.paragraph("valor) y algo mas")])
    }

    /// A full line can't have ended there, so the code on the next line is what it was leading to.
    @Test("code wrapped out of a list item stays in it, with its period outside the span")
    func wrappedOutOfItem() throws {
        let full = String(repeating: "palabra ", count: 11) + "metodo"
        let page = [
            TextLine(words: [word("9.", x: 40, y: 100)] + words(full, x: 54, y: 100)),
            line("toString().", x: 54, y: 112, font: .mono),
            TextLine(words: [word("10.", x: 40, y: 124)] + words("Otra cosa.", x: 54, y: 124)),
        ]
        #expect(try items(in: blocks(page)).map(\.text) == [full + " `toString()`.", "Otra cosa."])
    }

    private let url = "https://example.org/docs/page.html"

    @Test("a URL on its own line finishes the sentence leading to it")
    func displayedLink() {
        let page = [
            line("Para mas informacion sobre esto", x: 40, y: 76),
            line("y sobre lo otro que viene despues", x: 40, y: 88),
            line("se puede visitar", x: 40, y: 100),
            line(url, x: 60, y: 130, font: .mono),
            line("Y el texto sigue.", x: 40, y: 160),
        ]
        #expect(
            blocks(page) == [
                .paragraph(
                    "Para mas informacion sobre esto y sobre lo otro que viene despues"
                        + " se puede visitar `\(url)`"
                ),
                .paragraph("Y el texto sigue."),
            ]
        )
    }

    @Test(
        "a URL stays a listing after a colon, far from the text, or above more code",
        arguments: [
            ("Se puede ver esto:", 130.0, nil),
            ("Se puede visitar", 180.0, nil),
            ("Se puede visitar", 130.0, "curl -O page.html"),
        ] as [(String, Double, String?)]
    )
    func linkStaysListing(lead: String, y: Double, following: String?) {
        let found = blocks(
            [line(lead, x: 40, y: 100), line(url, x: 60, y: y, font: .mono)]
                + (following.map { [line($0, x: 60, y: y + 10, font: .mono)] } ?? [])
        )
        #expect(found.first == .paragraph(lead))
        #expect(found.count == 2)
        guard case .code(let code) = found.last else {
            Issue.record("expected code, got \(found)")
            return
        }
        #expect(code.first?.contains(url) == true)
    }

    @Test("a command after an unfinished sentence stays a listing")
    func commandIsNoLink() {
        let page = [
            line("Para compilar se ejecuta", x: 40, y: 100),
            line("javac Main.java", x: 60, y: 130, font: .mono),
        ]
        #expect(blocks(page).last == .code(["javac Main.java"]))
    }

    @Test("a span gives back the sentence's period, and keeps the semicolon of a statement")
    func spanPunctuation() {
        #expect(InlineRenderer.code(words("toString().", y: 100, font: .mono)) == "`toString()`.")
        #expect(InlineRenderer.code(words("int x = 5;", y: 100, font: .mono)) == "`int x = 5;`")
        #expect(InlineRenderer.code(words("...", y: 100, font: .mono)) == "`...`")
    }

    @Test("a command under a list item that ends its line early stays a listing")
    func commandUnderItem() {
        let page = [
            TextLine(words: [word("1.", x: 40, y: 100)] + words("Ejecuta esto:", x: 54, y: 100)),
            line("javac Main.java", x: 54, y: 112, font: .mono),
        ]
        #expect(
            blocks(page) == [
                .list([ListItem(depth: 0, marker: "1.", text: "Ejecuta esto:")]),
                .code(["javac Main.java"]),
            ]
        )
    }
}

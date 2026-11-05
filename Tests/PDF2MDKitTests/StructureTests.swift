import CoreGraphics
import Testing

@testable import PDF2MDKit

@Suite("TextNormalizer")
struct TextNormalizerTests {
    @Test(
        "text is normalized",
        arguments: [
            ("ﬁnal", "final"),
            ("eﬃcient ﬂow", "efficient flow"),
            ("Programaci´on", "Programación"),
            ("a˜no", "año"),
            ("ping¨uino", "pingüino"),
            ("d´ıa", "día"),
            ("Cafe\u{301}", "Café"),
            ("soft\u{AD}hyphen", "softhyphen"),
            ("non\u{A0}breaking", "non breaking"),
        ]
    )
    func normalizes(input: String, expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }

    @Test("a lone accent is left alone")
    func loneAccent() {
        #expect(TextNormalizer.normalize("it´s") == "it´s")
    }
}

@Suite("MarginFilter")
struct MarginFilterTests {
    @Test("a repeating numbered line stays when it's larger than the text, and goes when it isn't")
    func numberedHeadings() {
        let profile = DocumentProfile(
            pageCount: 10,
            bodySize: 10,
            headingBands: [],
            title: DocumentTitle(text: "t", lineTexts: []),
            repeatedMarginKeys: ["exercise", "#", "course notes"],
            repeatedImageDigests: [],
            isSlideDeck: false
        )
        let heading = line("Exercise 3", y: 30, size: 16)
        let header = line("Exercise 3", y: 30, size: 9)
        let bigNumber = line("12", y: 30, size: 16)
        let banner = line("Course notes", y: 30, size: 16)
        let middle = line("Exercise 3", y: 400, size: 9)
        #expect(!profile.isRunningMargin(heading, pageHeight: 800))
        #expect(profile.isRunningMargin(header, pageHeight: 800))
        #expect(profile.isRunningMargin(bigNumber, pageHeight: 800))
        #expect(profile.isRunningMargin(banner, pageHeight: 800))
        #expect(!profile.isRunningMargin(middle, pageHeight: 800))
    }

    @Test("code at a page's edge isn't a running margin, even when it repeats")
    func codeIsNotAMargin() {
        let profile = DocumentProfile(
            pageCount: 10,
            bodySize: 10,
            headingBands: [],
            title: DocumentTitle(text: "t", lineTexts: []),
            repeatedMarginKeys: ["}"],
            repeatedImageDigests: [],
            isSlideDeck: false
        )
        let brace = line("}", y: 780, size: 8, font: .mono)
        #expect(!profile.isRunningMargin(brace, pageHeight: 800))
    }

    @Test(
        "keys ignore digits and roman numerals",
        arguments: [
            ("Chapter 12", "chapter"),
            ("12 Chapter", "chapter"),
            ("Page 3 of 90", "page # of"),
            ("xiv", "#"),
            ("12", "#"),
            ("Book   Title", "book title"),
        ]
    )
    func keys(input: String, expected: String) {
        #expect(MarginFilter.key(for: input) == expected)
    }

    private func marginTracker(pages: Int, header: (Int) -> String?) -> MarginTracker {
        var tracker = MarginTracker(pageCount: pages)
        for page in 0..<pages {
            let keys = header(page).map { [MarginFilter.key(for: $0)] } ?? []
            tracker.add(page: page, keys: keys, isLandscape: false)
        }
        return tracker
    }

    @Test("a line on 30% of pages is removed, and below that it stays")
    func threshold() {
        let atThreshold = marginTracker(pages: 10) { $0 < 3 || $0 > 7 ? nil : nil }
        #expect(atThreshold.repeatedKeys().isEmpty)

        let thirty = marginTracker(pages: 10) { $0.isMultiple(of: 3) ? "Spaced header" : nil }
        #expect(thirty.repeatedKeys().contains("spaced header"))

        let twenty = marginTracker(pages: 10) { $0 == 0 || $0 == 5 ? "Rare header" : nil }
        #expect(twenty.repeatedKeys().isEmpty)
    }

    @Test("two-page documents keep their lines, however repetitive")
    func smallDocuments() {
        let tracker = marginTracker(pages: 2) { _ in "Same line" }
        #expect(tracker.repeatedKeys().isEmpty)
    }

    @Test("a chapter header on consecutive pages goes, even below 30% overall")
    func localRun() {
        let tracker = marginTracker(pages: 100) { (40..<44).contains($0) ? "Chapter Three" : nil }
        #expect(tracker.repeatedKeys().contains("chapter three"))
    }

    @Test("a bullet repeated across slide builds stays")
    func slideBuilds() {
        var tracker = MarginTracker(pageCount: 100)
        for page in 40..<44 {
            tracker.add(page: page, keys: ["last bullet"], isLandscape: true)
        }
        #expect(tracker.repeatedKeys().isEmpty)
    }

    @Test("counters are pruned, so memory doesn't follow the page count")
    func pruning() {
        var tracker = MarginTracker(pageCount: 10_000)
        for page in 0..<10_000 {
            tracker.add(page: page, keys: ["unique line \(words: page)"], isLandscape: false)
        }
        #expect(tracker.trackedKeyCount < 3100)
    }
}

extension String.StringInterpolation {
    /// Numbers would normalize away, so spell them as letters to make unique keys.
    fileprivate mutating func appendInterpolation(words value: Int) {
        appendLiteral(
            String(value).map { String(UnicodeScalar(97 + $0.wholeNumberValue!)!) }.joined()
        )
    }
}

@Suite("TitleResolver")
struct TitleResolverTests {
    @Test(
        "useless metadata is rejected",
        arguments: [
            "", "  ", "Untitled", "untitled document", "Microsoft Word - notes.docx",
            "PowerPoint Presentation", "Presentación de PowerPoint", "lecture3.pdf", "main.tex",
            "C:\\docs\\a.doc", "/home/me/a.dvi", "12345", "abc", "Slide 1",
        ]
    )
    func rejected(title: String) {
        #expect(!TitleResolver.isMeaningful(metadataTitle: title))
    }

    @Test(
        "real titles are kept",
        arguments: ["Foundations of Computing", "Álgebra Lineal", "C++ Primer", "Thinking in Java"]
    )
    func kept(title: String) {
        #expect(TitleResolver.isMeaningful(metadataTitle: title))
    }

    @Test("metadata wins, then the largest text on page 1, then the file name")
    func priority() {
        let page = [line("Big Title", y: 100, size: 24), line("body text here", y: 150)]
        #expect(
            TitleResolver.resolve(
                metadataTitle: "From Metadata",
                firstPageLines: page,
                bodySize: 10,
                fileName: "file"
            ).text == "From Metadata"
        )
        #expect(
            TitleResolver.resolve(
                metadataTitle: "Untitled",
                firstPageLines: page,
                bodySize: 10,
                fileName: "file"
            ).text == "Big Title"
        )
        #expect(
            TitleResolver.resolve(
                metadataTitle: nil,
                firstPageLines: [line("only body", y: 100)],
                bodySize: 10,
                fileName: "my notes"
            ).text == "my notes"
        )
    }

    @Test("a title wrapped over two lines is joined")
    func wrappedTitle() {
        let page = [
            line("A Very Long", y: 100, size: 24),
            line("Document Title", y: 128, size: 24),
            line("by someone", y: 170, size: 11),
        ]
        let title = TitleResolver.resolve(
            metadataTitle: nil,
            firstPageLines: page,
            bodySize: 10,
            fileName: "x"
        )
        #expect(title.text == "A Very Long Document Title")
        #expect(title.lineTexts == ["A Very Long", "Document Title"])
    }
}

@Suite("DocumentProfile")
struct DocumentProfileTests {
    private func profile(
        lines: [TextLine],
        pageSize: CGSize = CGSize(width: 612, height: 792)
    ) -> DocumentProfile {
        var builder = ProfileBuilder(pageCount: 1)
        builder.add(pageIndex: 0, pageSize: pageSize, lines: lines, images: [])
        return builder.finish(metadataTitle: "Metadata Title", fileName: "file")
    }

    private func bodyLines(count: Int = 20, size: Double = 10) -> [TextLine] {
        (0..<count).map {
            line(
                "body words that go on for a while on every single line",
                y: 200 + Double($0) * 14,
                size: size
            )
        }
    }

    @Test("the body size is the size with the most characters")
    func bodySize() {
        let lines = bodyLines() + [line("Short heading", y: 100, size: 18)]
        #expect(profile(lines: lines).bodySize == 10)
    }

    @Test("sizes above body rank into up to three levels")
    func ranks() {
        let lines =
            bodyLines() + [
                line("A", y: 100, size: 24), line("B", y: 110, size: 18),
                line("C", y: 120, size: 14), line("D", y: 130, size: 12),
            ]
        let result = profile(lines: lines)
        #expect(result.headingLevel(forSize: 24) == 2)
        #expect(result.headingLevel(forSize: 18) == 3)
        #expect(result.headingLevel(forSize: 14) == 4)
        #expect(result.headingLevel(forSize: 12) == 4)
        #expect(result.headingLevel(forSize: 10) == nil)
        #expect(result.headingLevel(forSize: 8) == nil)
    }

    @Test("near-identical sizes share a level")
    func clustering() {
        let lines =
            bodyLines() + [
                line("A", y: 100, size: 17), line("B", y: 110, size: 13.5),
                line("C", y: 120, size: 14), line("D", y: 130, size: 11.5),
            ]
        let result = profile(lines: lines)
        #expect(result.headingLevel(forSize: 13.5) == result.headingLevel(forSize: 14))
        #expect(result.headingLevel(forSize: 11.5) == 4)
    }

    @Test("a large size used for long lines isn't a heading")
    func longLinesAreNotHeadings() {
        let lines =
            bodyLines(count: 30) + bodyLines(count: 10, size: 13) + [line("H", y: 100, size: 20)]
        let result = profile(lines: lines)
        #expect(result.headingLevel(forSize: 13) == nil)
        #expect(result.headingLevel(forSize: 20) == 2)
    }

    @Test("landscape documents are slide decks")
    func slideDeck() {
        #expect(profile(lines: bodyLines(), pageSize: CGSize(width: 960, height: 540)).isSlideDeck)
        #expect(!profile(lines: bodyLines()).isSlideDeck)
    }
}

@Suite("BlockBuilder")
struct BlockBuilderTests {
    private func blocks(
        _ lines: [TextLine],
        bodySize: Double = 10,
        levels: [HeadingBand] = [],
        isSlide: Bool = false
    ) -> [Block] {
        let profile = DocumentProfile(
            pageCount: 1,
            bodySize: bodySize,
            headingBands: levels,
            title: DocumentTitle(text: "T", lineTexts: []),
            repeatedMarginKeys: [],
            repeatedImageDigests: [],
            isSlideDeck: isSlide
        )
        return BlockBuilder(profile: profile).blocks(from: lines, isSlidePage: isSlide)
    }

    @Test("wrapped lines reflow into one paragraph")
    func reflow() {
        let result = blocks([line("first line of it", y: 100), line("and the second", y: 112)])
        #expect(result == [.paragraph("first line of it and the second")])
    }

    @Test("a large vertical gap starts a new paragraph")
    func paragraphGap() {
        let result = blocks([
            line("first paragraph.", y: 100), line("still first.", y: 112),
            line("second paragraph.", y: 140), line("still second.", y: 152),
        ])
        #expect(
            result == [
                .paragraph("first paragraph. still first."),
                .paragraph("second paragraph. still second."),
            ]
        )
    }

    @Test("end-of-line hyphens join, and real hyphens before capitals stay")
    func hyphens() {
        #expect(
            blocks([line("a compre-", y: 100), line("hensive habit", y: 112)])
                == [.paragraph("a comprehensive habit")]
        )
        #expect(
            blocks([line("the Hewlett-", y: 100), line("Packard printer", y: 112)])
                == [.paragraph("the Hewlett-Packard printer")]
        )
    }

    @Test("many short paragraphs don't hide the leading, so their gaps still split them")
    func gapsAmongShortParagraphs() {
        // More paragraph gaps than line gaps, which is common on a page of definitions.
        let result = blocks([
            line(fullWidthText, y: 100), line("first ends.", y: 112),
            line(fullWidthText, y: 132), line("second ends", y: 144),
            line("third starts here,", y: 164),
            line("fourth starts here,", y: 184),
            line("fifth starts here", y: 204),
        ])
        #expect(result.count == 5, "\(result)")
    }

    private let fullWidthText =
        "a full line of running text that reaches all the way across the page"

    @Test("a hanging indent continues its paragraph")
    func hangingIndent() {
        let result = blocks([
            line("Term " + fullWidthText, y: 100),
            line("and goes on under an indent", x: 96, y: 112),
            line("for one more line.", x: 96, y: 124),
        ])
        #expect(
            result == [
                .paragraph(
                    "Term " + fullWidthText + " and goes on under an indent for one more line."
                )
            ]
        )
    }

    @Test("a hanging indent continues even after a line that ends in a period")
    func hangingAfterPeriod() {
        let result = blocks([
            line("Term " + fullWidthText + ".", y: 100),
            line("And goes on under an indent", x: 96, y: 112),
            line("for one more line.", x: 96, y: 124),
        ])
        #expect(
            result == [
                .paragraph(
                    "Term " + fullWidthText + ". And goes on under an indent for one more line."
                )
            ]
        )
    }

    @Test("a bold lead-in keeps its bold")
    func boldLeadIn() {
        let lineWithTerm = TextLine(
            words: [word("Term", x: 72, y: 100, font: .bold)]
                + words("explained in plain text.", x: 100, y: 100)
        )
        #expect(blocks([lineWithTerm]) == [.paragraph("**Term** explained in plain text.")])
    }

    @Test("a bold lead-in keeps its bold in a list item")
    func boldLeadInListItem() {
        let item = TextLine(
            words: [word("•", x: 72, y: 100), word("Term", x: 82, y: 100, font: .bold)]
                + words("explained in plain text.", x: 110, y: 100)
        )
        let expected = ListItem(depth: 0, marker: "-", text: "**Term** explained in plain text.")
        #expect(blocks([item]) == [.list([expected])])
    }

    @Test("code wrapped from a full line of text stays in its paragraph")
    func wrappedInlineCode() {
        let lastWord = word("arreglo.", x: 400, y: 100, font: .mono)
        let first = TextLine(words: words(fullWidthText, y: 100) + [lastWord])
        let tail = TextLine(words: [word("length", x: 72, y: 112, font: .mono)])
        #expect(blocks([first, tail]) == [.paragraph(fullWidthText + " `arreglo.` `length`")])
    }

    @Test("a URL wrapped across lines is rejoined")
    func wrappedURL() {
        let url = word("http://creative.", x: 400, y: 100, font: .mono)
        let first = TextLine(words: words(fullWidthText, y: 100) + [url])
        let tail = TextLine(words: [word("org/licenses/", x: 72, y: 112, font: .mono)])
        let expected = fullWidthText + " `http://creative.org/licenses/`"
        #expect(blocks([first, tail]) == [.paragraph(expected)])
    }

    @Test("a code line after a short line of text is a block, not a wrapped word")
    func codeAfterShortLine() {
        let intro = line("Por ejemplo:", y: 100)
        let code = TextLine(words: [word("java", x: 72, y: 112, font: .mono)])
        #expect(blocks([intro, code]) == [.paragraph("Por ejemplo:"), .code(["java"])])
    }

    @Test("a listing right after a full line of text is still a block")
    func listingAfterFullLine() {
        let intro = line(fullWidthText, y: 100)
        let first = TextLine(words: [word("java", x: 72, y: 112, font: .mono)])
        let second = TextLine(words: [word("Main", x: 72, y: 124, font: .mono)])
        #expect(
            blocks([intro, first, second]) == [.paragraph(fullWidthText), .code(["java", "Main"])]
        )
    }

    @Test("a first-line indent starts a new paragraph without any gap")
    func indent() {
        let result = blocks([
            line("a full line ending here with enough words to fill the measure.", x: 72, y: 100),
            line("a new paragraph starting with an indent and a lot of words", x: 90, y: 112),
            line("that wraps back to the margin.", x: 72, y: 124),
        ])
        #expect(result.count == 2)
    }

    @Test("sized lines become headings at their rank")
    func headings() {
        let levels = [HeadingBand(minSize: 16, maxSize: 18, level: 2)]
        let result = blocks(
            [line("Section", y: 80, size: 17), line("text", y: 110)],
            levels: levels
        )
        #expect(result == [.heading(level: 2, text: "Section"), .paragraph("text")])
    }

    @Test("a wrapped heading joins, but two headings stay separate")
    func wrappedHeading() {
        let levels = [HeadingBand(minSize: 16, maxSize: 18, level: 2)]
        let wrapped = blocks(
            [line("Long section", y: 80, size: 17), line("title here", y: 100, size: 17)],
            levels: levels
        )
        #expect(wrapped == [.heading(level: 2, text: "Long section title here")])
        let separate = blocks(
            [line("One", y: 80, size: 17), line("body", y: 110), line("Two", y: 140, size: 17)],
            levels: levels
        )
        #expect(separate.count == 3)
    }

    @Test("a fully bold short line is a heading at the next free level")
    func boldHeading() {
        let levels = [HeadingBand(minSize: 16, maxSize: 18, level: 2)]
        let result = blocks(
            [line("Bold label", y: 80, font: .bold), line("text", y: 110)],
            levels: levels
        )
        #expect(result.first == .heading(level: 3, text: "Bold label"))
    }

    @Test("a bold sentence stays a paragraph")
    func boldSentence() {
        let result = blocks([line("This whole line is a bold sentence.", y: 80, font: .bold)])
        #expect(result == [.paragraph("This whole line is a bold sentence.")])
    }

    @Test("digits at heading size are not a heading")
    func digitsAreNotHeadings() {
        let levels = [HeadingBand(minSize: 16, maxSize: 18, level: 2)]
        #expect(blocks([line("2026", y: 80, size: 17)], levels: levels) == [.paragraph("2026")])
    }

    @Test("bullets nest by indent, and wrapped items continue")
    func lists() {
        let result = blocks([
            line("• top item", x: 80, y: 100),
            line("◦ nested item", x: 98, y: 112),
            line("• second top", x: 80, y: 124),
            line("wraps here", x: 92, y: 136),
        ])
        #expect(
            result == [
                .list([
                    ListItem(depth: 0, marker: "-", text: "top item"),
                    ListItem(depth: 1, marker: "-", text: "nested item"),
                    ListItem(depth: 0, marker: "-", text: "second top wraps here"),
                ])
            ]
        )
    }

    @Test("numbering and Wingdings bullets are recognized")
    func markers() {
        let numbered = blocks([line("1. first", y: 100), line("2) second", y: 112)])
        #expect(
            numbered == [
                .list([
                    ListItem(depth: 0, marker: "1.", text: "first"),
                    ListItem(depth: 0, marker: "2.", text: "second"),
                ])
            ]
        )
        let wingdings = blocks([line("\u{F0B7} item", y: 100)])
        #expect(wingdings == [.list([ListItem(depth: 0, marker: "-", text: "item")])])
    }

    @Test("not a list: a decimal, a hyphenated word or a lone marker")
    func notLists() {
        #expect(blocks([line("3.5 is a number", y: 100)]) == [.paragraph("3.5 is a number")])
        #expect(blocks([line("well-known fact", y: 100)]) == [.paragraph("well-known fact")])
        #expect(blocks([line("•", y: 100)]) == [])
    }

    @Test("monospace lines fence, keeping indentation and spacing from geometry")
    func code() {
        let cell = 5.0
        let result = blocks([
            line("if (x) {", x: 72, y: 100, font: .mono),
            line("return 1;", x: 72 + 4 * cell, y: 112, font: .mono),
            line("}", x: 72, y: 124, font: .mono),
        ])
        #expect(result == [.code(["if (x) {", "    return 1;", "}"])])
    }

    @Test("a blank line inside code is preserved once")
    func codeBlankLine() {
        let result = blocks([
            line("a();", x: 72, y: 100, font: .mono),
            line("b();", x: 72, y: 124, font: .mono),
            line("c();", x: 72, y: 136, font: .mono),
        ])
        #expect(result == [.code(["a();", "", "b();", "c();"])])
    }

    @Test("inline code holding backticks gets a longer fence that CommonMark can read")
    func inlineCodeWithBackticks() {
        let input = TextLine(words: [
            word("usa", x: 72, y: 100),
            word("``hola''", x: 90, y: 100, font: .mono),
            word("aqui", x: 140, y: 100),
        ])
        #expect(blocks([input]) == [.paragraph("usa ``` ``hola'' ``` aqui")])
    }

    @Test("a lone backtick in inline code still gets a double fence")
    func inlineCodeWithOneBacktick() {
        let input = TextLine(words: [
            word("usa", x: 72, y: 100),
            word("a`b", x: 90, y: 100, font: .mono),
        ])
        #expect(blocks([input]) == [.paragraph("usa ``a`b``")])
    }

    @Test("monospace words in prose become inline code")
    func inlineCode() {
        let input = TextLine(
            words: words("call the", y: 100) + words("next()", x: 120, y: 100, font: .mono)
                + words("method", x: 155, y: 100)
        )
        #expect(blocks([input]) == [.paragraph("call the `next()` method")])
    }

    @Test("markdown characters are escaped")
    func escaping() {
        #expect(
            blocks([line("a *b* [c] <d> $e snake_case _f_", y: 100)])
                == [.paragraph(#"a \*b\* \[c\] \<d> \$e snake_case \_f\_"#)]
        )
        #expect(blocks([line("# not heading", y: 100)]) == [.paragraph(##"\# not heading"##)])
    }

    @Test("a slide's top line becomes the title heading")
    func slideTitle() {
        let result = blocks(
            [
                line("Slide Title", y: 60, size: 30),
                line("• a bullet here", x: 70, y: 120, size: 20),
                line("• another bullet", x: 70, y: 150, size: 20),
            ],
            bodySize: 20,
            isSlide: true
        )
        #expect(result.first == .heading(level: 2, text: "Slide Title"))
        #expect(result.count == 2)
    }

    @Test("a slide without larger text gets no invented title")
    func slideWithoutTitle() {
        let result = blocks(
            [line("just some words", y: 60, size: 20), line("and more words", y: 120, size: 20)],
            bodySize: 20,
            isSlide: true
        )
        #expect(!result.contains { if case .heading = $0 { true } else { false } })
    }
}

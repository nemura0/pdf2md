import CoreGraphics
import Testing

@testable import PDF2MDKit

@Suite("Outline")
struct OutlineTests {
    private func entry(_ label: String, depth: Int = 1, page: Int = 0) -> OutlineEntry {
        OutlineEntry(pageIndex: page, depth: depth, label: label)
    }

    private func marked(_ lines: [TextLine], _ entries: [OutlineEntry]) -> [TextLine] {
        OutlineMatcher.marking(lines, with: entries, minimumSize: 10.8)
            .filter { $0.outlineLevel != nil }
    }

    @Test(
        "a label loses what LaTeX's colorbox leaks into it",
        arguments: [
            ("=0ptdarkgray!20final", "final"),
            ("Usando el =0ptdarkgray!20Sistema", "Usando el Sistema"),
            ("La variable =0ptdarkgray!20JAVA_HOME", "La variable JAVA_HOME"),
            ("Uso de IllegalArgumentException", "Uso de IllegalArgumentException"),
            ("  Two   spaces ", "Two spaces"),
        ]
    )
    func cleansLabels(raw: String, expected: String) {
        #expect(OutlineLabel.clean(raw) == expected)
    }

    @Test("a heading keeps the number printed in front of it, and its level comes from depth")
    func numberedHeading() throws {
        let result = marked(
            [
                line("1.6. Datos y sus tipos", y: 100, size: 14, font: .bold),
                line("Datos y sus tipos son importantes", y: 120),
            ],
            [entry("Datos y sus tipos", depth: 2)]
        )
        let heading = try #require(result.first)
        #expect(result.count == 1)
        #expect(heading.text == "1.6. Datos y sus tipos")
        #expect(heading.outlineLevel == 4)
    }

    @Test("the real heading wins over a running header holding the same words")
    func prefersTheHeading() throws {
        let result = marked(
            [
                line("1.6. DATOS Y SUS TIPOS", y: 25, size: 10),
                line("1.6. Datos y sus tipos", y: 100, size: 14, font: .bold),
            ],
            [entry("Datos y sus tipos")]
        )
        #expect(try #require(result.first).baseline == 100)
    }

    @Test("body text holding the label's words isn't its heading")
    func ignoresBodyText() {
        #expect(marked([line("Ciclos", y: 100)], [entry("Ciclos")]).isEmpty)
    }

    @Test("a bold line at body size can be a heading")
    func boldAtBodySize() {
        #expect(marked([line("Ciclos", y: 100, font: .bold)], [entry("Ciclos")]).count == 1)
    }

    @Test("a title on two lines becomes one heading, with the chapter number above it")
    func wrappedChapterTitle() throws {
        let result = marked(
            [
                line("2", y: 140, size: 20, font: .bold),
                line("Introduccion a la Ingenieria de", y: 197, size: 24, font: .bold),
                line("Software", y: 227, size: 24, font: .bold),
                line("2.1. Introduccion", y: 293, size: 14, font: .bold),
            ],
            [entry("Introduccion a la Ingenieria de Software", depth: 1)]
        )
        #expect(result.count == 1)
        #expect(try #require(result.first).text == "2 Introduccion a la Ingenieria de Software")
    }

    @Test("a part's label spans the line naming the part and the part's title")
    func partTitle() throws {
        let result = marked(
            [
                line("Parte I", y: 250, size: 20, font: .bold),
                line("Libro Guia", y: 308, size: 24, font: .bold),
            ],
            [entry("I Libro Guia", depth: 0)]
        )
        let heading = try #require(result.first)
        #expect(heading.text == "Parte I Libro Guia")
        #expect(heading.outlineLevel == 2)
    }

    @Test("a page number above a heading stays out of it")
    func pageNumberAboveHeading() throws {
        let result = marked(
            [
                line("23", y: 25, size: 10),
                line("Ciclos", y: 57, size: 14, font: .bold),
            ],
            [entry("Ciclos")]
        )
        #expect(try #require(result.first).text == "Ciclos")
    }

    @Test("an appendix's letter counts as its number")
    func appendixLetter() throws {
        let result = marked(
            [
                line("Apendice A", y: 140, size: 20, font: .bold),
                line("Instalacion del JDK", y: 197, size: 24, font: .bold),
            ],
            [entry("Instalacion del JDK")]
        )
        #expect(try #require(result.first).text == "Apendice A Instalacion del JDK")
    }

    @Test("a heading just below another one stays apart when the other has no number")
    func headingAboveHeading() throws {
        let result = marked(
            [
                line("Prefacio", y: 140, size: 20, font: .bold),
                line("Agradecimientos", y: 180, size: 14, font: .bold),
            ],
            [entry("Agradecimientos")]
        )
        #expect(try #require(result.first).text == "Agradecimientos")
    }

    @Test("two entries with one label take one line each")
    func repeatedLabel() {
        let result = marked(
            [
                line("Ejercicios", y: 100, size: 14, font: .bold),
                line("Ejercicios", y: 300, size: 14, font: .bold),
            ],
            [entry("Ejercicios"), entry("Ejercicios")]
        )
        #expect(result.count == 2)
    }

    @Test("deep entries stop at the deepest heading Markdown has")
    func deepEntry() throws {
        let result = marked(
            [line("Deep", y: 100, size: 14, font: .bold)],
            [entry("Deep", depth: 9)]
        )
        #expect(try #require(result.first).outlineLevel == 6)
    }

    // MARK: Profile

    private func bodyLines(y: Double = 200) -> [TextLine] {
        (0..<20).map {
            line(
                "body words that go on for a while on every single line",
                y: y + Double($0) * 14
            )
        }
    }

    private func book(outline: [OutlineEntry], matching titles: [String]) -> DocumentProfile {
        var builder = ProfileBuilder(pageCount: 20, outline: outline)
        let size = CGSize(width: 480, height: 680)
        let cover = [
            line("Cover", y: 80, size: 56, font: .bold),
            line("Subtitle", y: 200, size: 49, font: .bold),
        ]
        builder.add(pageIndex: 0, pageSize: size, lines: cover, images: [])
        for (offset, title) in titles.enumerated() {
            let lines =
                [line(title, y: 100, size: 14, font: .bold)] + bodyLines()
                + [line("Software = Programas", y: 500, size: 14)]
            builder.add(pageIndex: offset + 1, pageSize: size, lines: lines, images: [])
        }
        return builder.finish(metadataTitle: nil, fileName: "book")
    }

    @Test("an outline that matches the pages decides the heading sizes, in bold only")
    func trustedOutline() {
        let titles = ["Uno", "Dos", "Tres", "Cuatro"]
        let outline = titles.enumerated().map { entry($1, depth: 1, page: $0 + 1) }
        let profile = book(outline: outline, matching: titles)
        #expect(profile.outlineEntries(onPage: 1) == [outline[0]])
        #expect(profile.headingLevel(for: line("Otro", y: 1, size: 14, font: .bold)) == 3)
        #expect(profile.headingLevel(for: line("Software", y: 1, size: 14)) == nil)
        #expect(profile.headingLevel(for: line("Cover", y: 1, size: 56, font: .bold)) == nil)
    }

    @Test("the running header above a heading doesn't decide that heading's style")
    func runningHeadAboveHeading() {
        var builder = ProfileBuilder(
            pageCount: 6,
            outline: ["Uno", "Dos", "Tres", "Cuatro"].enumerated().map {
                entry($1, depth: 1, page: $0)
            }
        )
        for (page, title) in ["Uno", "Dos", "Tres", "Cuatro"].enumerated() {
            let lines =
                [
                    line("1. CAPITULO", y: 25),
                    line(title, y: 57, size: 14, font: .bold),
                ] + bodyLines()
            builder.add(
                pageIndex: page,
                pageSize: CGSize(width: 480, height: 680),
                lines: lines,
                images: []
            )
        }
        let profile = builder.finish(metadataTitle: "Metadata", fileName: "book")
        #expect(profile.headingLevel(for: line("Software", y: 1, size: 14)) == nil)
    }

    @Test("a few regular headings among many bold ones don't make regular text at that size one")
    func mostlyBoldHeadings() {
        let titles = (1...8).map { "Seccion \($0)x" }
        var builder = ProfileBuilder(
            pageCount: 20,
            outline: (titles + ["final"]).enumerated().map { entry($1, depth: 1, page: $0) }
        )
        let size = CGSize(width: 480, height: 680)
        for (page, title) in titles.enumerated() {
            let lines = [line(title, y: 100, size: 14, font: .bold)] + bodyLines()
            builder.add(pageIndex: page, pageSize: size, lines: lines, images: [])
        }
        builder.add(
            pageIndex: titles.count,
            pageSize: size,
            lines: [line("final", y: 100, size: 14)] + bodyLines(),
            images: []
        )
        let profile = builder.finish(metadataTitle: "Metadata", fileName: "book")
        #expect(profile.headingLevel(for: line("Software", y: 1, size: 14)) == nil)
        #expect(profile.headingLevel(for: line("Software", y: 1, size: 14, font: .bold)) == 3)
    }

    @Test("an outline that doesn't match the pages is ignored")
    func untrustedOutline() {
        let titles = ["Uno", "Dos", "Tres", "Cuatro"]
        let outline = (1...10).map { entry("Bookmark \($0)", page: $0) }
        let profile = book(outline: outline, matching: titles)
        #expect(profile.outlineEntries(onPage: 1).isEmpty)
        #expect(profile.headingLevel(forSize: 14) != nil)
    }

    @Test("a slide deck's titles aren't taken from its outline")
    func slidesIgnoreTheOutline() {
        var builder = ProfileBuilder(
            pageCount: 4,
            outline: (0..<4).map { entry("Title \($0)", page: $0) }
        )
        for page in 0..<4 {
            builder.add(
                pageIndex: page,
                pageSize: CGSize(width: 960, height: 540),
                lines: [line("Title \(page)", y: 50, size: 30, font: .bold)] + bodyLines(),
                images: []
            )
        }
        #expect(builder.finish(metadataTitle: nil, fileName: "d").outlineEntries(onPage: 0).isEmpty)
    }

    // MARK: No outline

    @Test("without an outline, a size used on one page of a long document gets no rank")
    func rareSizesDontTakeARank() {
        var builder = ProfileBuilder(pageCount: 20)
        let size = CGSize(width: 480, height: 680)
        builder.add(
            pageIndex: 0,
            pageSize: size,
            lines: [line("Cover", y: 80, size: 56), line("Author", y: 200, size: 30)],
            images: []
        )
        for page in 1...10 {
            builder.add(
                pageIndex: page,
                pageSize: size,
                lines: [line("Section", y: 100, size: 14)] + bodyLines(),
                images: []
            )
        }
        let profile = builder.finish(metadataTitle: "Metadata", fileName: "book")
        #expect(profile.headingLevel(forSize: 14) == 2)
        #expect(profile.headingLevel(forSize: 56) == nil)
        #expect(profile.headingLevel(forSize: 30) == nil)
    }

    @Test("a lone chapter number doesn't count as a heading size")
    func numbersDontTakeARank() {
        var builder = ProfileBuilder(pageCount: 20)
        for page in 0..<10 {
            builder.add(
                pageIndex: page,
                pageSize: CGSize(width: 480, height: 680),
                lines: [line("\(page + 1)", y: 60, size: 20), line("Section", y: 100, size: 14)]
                    + bodyLines(),
                images: []
            )
        }
        let profile = builder.finish(metadataTitle: "Metadata", fileName: "book")
        #expect(profile.headingLevel(forSize: 14) == 2)
    }

    /// A real page has a handful. Twenty thousand on a page of 3,000 lines would take minutes.
    @Test("a page's entries are limited, so a hostile outline can't hold up a conversion")
    func entriesPerPage() {
        let lines = (0..<300).map { index in
            line("Seccion \(index)", y: 100 + Double(index) * 20, size: 14)
        }
        let entries = (0..<300).map { index in
            OutlineEntry(pageIndex: 0, depth: 1, label: "Seccion \(index)")
        }
        let marked = OutlineMatcher.marking(lines, with: entries, minimumSize: 12)
        #expect(marked.filter { $0.outlineLevel != nil }.count == 200)
    }
}

@Suite("Running heads")
struct RunningHeadTests {
    private let size = CGSize(width: 480, height: 680)

    private func page(head: String, firstLineGap: Double = 30) -> [TextLine] {
        [line(head, y: 25.7)]
            + (0..<30).map {
                line(
                    "body words that go on for a while on every single line",
                    y: 25.7 + firstLineGap + Double($0) * 12
                )
            }
    }

    @Test("a header that changes with every section goes, by its place on the page")
    func changingHeaders() {
        var builder = ProfileBuilder(pageCount: 10)
        for index in 0..<10 {
            builder.add(
                pageIndex: index,
                pageSize: size,
                lines: page(head: "\(index).\(index) Different words \(index * 7) x\(index)"),
                images: []
            )
        }
        let profile = builder.finish(metadataTitle: "Metadata", fileName: "f")
        #expect(profile.isRunningMargin(line("1.6. DATOS Y SUS TIPOS", y: 25.7), pageHeight: 680))
        #expect(!profile.isRunningMargin(line("Datos y sus tipos", y: 200), pageHeight: 680))
        #expect(
            !profile.isRunningMargin(
                line("Big heading", y: 25.7, size: 14),
                pageHeight: 680
            )
        )
        #expect(
            !profile.isRunningMargin(
                line("Bold heading", y: 25.7, font: .bold),
                pageHeight: 680
            )
        )
    }

    @Test("a page's first line of text isn't a header just because it starts every page")
    func bodyTextAtTheTop() {
        var builder = ProfileBuilder(pageCount: 10)
        for index in 0..<10 {
            builder.add(
                pageIndex: index,
                pageSize: size,
                lines: page(head: "Words on the first line \(index)", firstLineGap: 12),
                images: []
            )
        }
        let profile = builder.finish(metadataTitle: "Metadata", fileName: "f")
        #expect(!profile.isRunningMargin(line("Some other text", y: 25.7), pageHeight: 680))
    }

    @Test("a slide's title isn't a header")
    func slidesKeepTitles() {
        var builder = ProfileBuilder(pageCount: 10)
        for index in 0..<10 {
            builder.add(
                pageIndex: index,
                pageSize: CGSize(width: 960, height: 540),
                lines: page(head: "Slide title \(index)x"),
                images: []
            )
        }
        let profile = builder.finish(metadataTitle: "Metadata", fileName: "f")
        #expect(!profile.isRunningMargin(line("Another title", y: 25.7), pageHeight: 540))
    }
}

@Suite("Printed table of contents")
struct TableOfContentsTests {
    private func entry(_ title: String, page: Int, y: Double) -> TextLine {
        line("\(title) . . . . . . . . . . . . \(page)", y: y)
    }

    @Test("a page of dot leaders with rising page numbers is a table of contents")
    func listing() {
        let lines =
            [line("Indice general", y: 50, size: 24, font: .bold)]
            + (0..<6).map { entry("Section \($0)", page: 10 + $0 * 3, y: 100 + Double($0) * 12) }
        #expect(TableOfContents.isListing(lines))
    }

    @Test("a page number can sit apart from its leader")
    func separateNumbers() {
        let lines = (0..<6).flatMap { index -> [TextLine] in
            let y = 100 + Double(index) * 12
            return [
                line("Section \(index) . . . . . . . . . . . .", y: y),
                line("\(10 + index)", x: 400, y: y),
            ]
        }
        #expect(TableOfContents.isListing(lines))
    }

    @Test("a price list isn't one, since its numbers don't rise")
    func priceList() {
        let prices = [30, 12, 45, 9, 22, 18]
        let lines = prices.enumerated().map {
            entry("Item \($0)", page: $1, y: 100 + Double($0) * 12)
        }
        #expect(!TableOfContents.isListing(lines))
    }

    @Test("a page of prose with a few leaders isn't one")
    func prose() {
        let leaders = (0..<5).map { entry("Section \($0)", page: $0, y: 100 + Double($0) * 12) }
        let text = (0..<12).map {
            line("Plain words of running text here", y: 200 + Double($0) * 12)
        }
        #expect(!TableOfContents.isListing(leaders + text))
    }

    @Test("a few leaders alone aren't enough")
    func tooFew() {
        let lines = (0..<4).map { entry("Section \($0)", page: $0, y: 100 + Double($0) * 12) }
        #expect(!TableOfContents.isListing(lines))
    }
}

@Suite("A whole book")
struct OutlineBookTests {
    private func convert(_ name: String) async throws -> (String, ConversionReport) {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, report, _) = try await harness.convert(try TestFixtures.named(name))
        return (markdown, report)
    }

    private func headings(in markdown: String) -> [String] {
        markdown.split(separator: "\n").map(String.init).filter { $0.hasPrefix("#") }
    }

    @Test("headings come from the outline, with their numbers and their depth")
    func hierarchy() async throws {
        let (markdown, _) = try await convert("outline-book.pdf")
        #expect(
            headings(in: markdown) == [
                "# Programacion",
                "## Parte I Libro Guia",
                "### 1 Nivelacion",
                "#### 1.1. Que es Java",
                "##### 1.1.1. final",
                "#### 1.2. Datos y sus tipos",
                "### 2 Introduccion a la Ingenieria de Software",
                "#### 2.1. Calidad",
            ]
        )
    }

    @Test("the cover's large lines and a display line at a heading's size are just text")
    func falseHeadings() async throws {
        let (markdown, _) = try await convert("outline-book.pdf")
        for text in ["Libro Guia", "0.3b", "Eric Ross", "Software = Programas"] {
            #expect(markdown.contains("\n\(text)\n"), "\(text)")
        }
    }

    @Test("the printed table of contents is gone")
    func noContentsPage() async throws {
        let (markdown, _) = try await convert("outline-book.pdf")
        #expect(!markdown.contains(". . ."))
        #expect(!markdown.contains("Indice general"))
    }

    @Test("headers that change with the section are gone")
    func noRunningHeads() async throws {
        let (markdown, _) = try await convert("outline-book.pdf")
        for text in ["QUE ES JAVA", "INTRODUCCION A LA INGENIERIA", "Programacion Orientada"] {
            #expect(!markdown.contains(text), "\(text)")
        }
    }

    @Test("a blank page costs no Vision call and leaves no page marker")
    func blankPage() async throws {
        let (markdown, report) = try await convert("outline-book.pdf")
        #expect(report.stats.ocrPages == 0)
        #expect(report.stats.failedPages == 0)
        #expect(!markdown.contains("<!-- page 7 -->"))
        #expect(!markdown.contains("<!-- page 2 -->"))
    }

    @Test("without an outline, sizes still give the sections a hierarchy, past the cover")
    func withoutOutline() async throws {
        let (markdown, _) = try await convert("unoutlined-book.pdf")
        let found = headings(in: markdown)
        #expect(found.contains("## Nivelacion"))
        #expect(found.contains("#### 1.1. Que es Java"))
        #expect(!found.contains { $0.hasSuffix(" 0.3b") })
        #expect(!markdown.contains(". . ."))
    }
}

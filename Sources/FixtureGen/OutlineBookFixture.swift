import Foundation

/// A book with what a real LaTeX book has around its text: a cover in huge type, a printed table
/// of contents, running headers that change with the section, a chapter number on its own line,
/// and a PDF outline. One copy has the outline and one doesn't, so both ways of finding headings
/// can be checked on the same pages.
enum OutlineBookFixture {
    private struct Node {
        var title: String
        var page: Int
        var children: [Node] = []
    }

    private static let pageHeight = 680.0
    private static let textX = 34.0
    private static let bodyTop = 620.0
    private static let bodyLeading = 12.0

    /// Labels as LaTeX's hyperref writes them, including a `\colorbox` that leaked into one.
    private static let outline = [
        Node(
            title: "I Libro Guia",
            page: 3,
            children: [
                Node(
                    title: "Nivelacion",
                    page: 4,
                    children: [
                        Node(
                            title: "Que es Java",
                            page: 4,
                            children: [Node(title: "=0ptdarkgray!20final", page: 5)]
                        ),
                        Node(title: "Datos y sus tipos", page: 5),
                    ]
                ),
                Node(
                    title: "Introduccion a la Ingenieria de Software",
                    page: 7,
                    children: [Node(title: "Calidad", page: 8)]
                ),
            ]
        )
    ]

    private static func font(_ name: String, flags: Int, width: Int) -> String {
        let widths = Array(repeating: String(width), count: 224).joined(separator: " ")
        return """
            << /Type /Font /Subtype /Type1 /BaseFont /\(name) /FirstChar 32 /LastChar 255 \
            /Widths [\(widths)] /Encoding /WinAnsiEncoding /FontDescriptor << \
            /Type /FontDescriptor /FontName /\(name) /Flags \(flags) \
            /FontBBox [-420 -281 1431 1167] /ItalicAngle 0 /Ascent 850 /Descent -230 \
            /CapHeight 700 /StemV 80 >> >>
            """
    }

    private static func fonts() -> String {
        """
        /Sans \(font("ABCDEF+LMSans10-Regular", flags: 32, width: 450)) \
        /Bold \(font("ABCDEF+LMSans10-Bold", flags: 262176, width: 500))
        """
    }

    private static func text(
        _ string: String,
        font: String = "Sans",
        size: Double = 9.963,
        x: Double = textX,
        y: Double
    ) -> String {
        "BT /\(font) \(size) Tf \(x) \(y) Td (\(string)) Tj ET\n"
    }

    private static func head(section: String) -> String {
        text("Programacion Orientada", y: pageHeight - 25.7)
            + text(section, x: 300, y: pageHeight - 25.7)
    }

    private static func paragraph(_ words: String, lines: Int, top: Double = bodyTop) -> String {
        (0..<lines).map { index in
            text(
                "\(words) line number \(index) of this paragraph",
                y: top - Double(index) * bodyLeading
            )
        }.joined()
    }

    private static func contents() -> String {
        let sections = [
            ("1.1. Que es Java", 5), ("1.2. Datos y sus tipos", 6), ("1.3. Ciclos", 9),
            ("2.1. Calidad", 9), ("2.2. Depuracion", 11), ("2.3. Validacion", 14),
        ]
        let leader = String(repeating: " .", count: 30)
        return text("Indice general", font: "Bold", size: 24.8, y: 540)
            + sections.enumerated().map { offset, section in
                text("\(section.0)\(leader) \(section.1)", y: 500 - Double(offset) * bodyLeading)
            }.joined()
    }

    private static func pages() -> [String] {
        let chapterTwoHead = head(section: "2. INTRODUCCION A LA INGENIERIA")
        return [
            text("Programacion", font: "Bold", size: 56.8, y: 595)
                + text("Libro Guia", font: "Bold", size: 49.8, y: 266)
                + text("0.3b", size: 29.9, x: 6, y: 174)
                + text("Eric Ross", font: "Bold", size: 29.9, x: 107, y: 65),
            contents(),
            head(section: "INDICE GENERAL") + paragraph("Preface text", lines: 4),
            text("Parte I", font: "Bold", size: 20.7, x: 214, y: 430)
                + text("Libro Guia", font: "Bold", size: 24.8, x: 188, y: 372),
            text("1", font: "Bold", size: 20.7, y: 540)
                + text("Nivelacion", font: "Bold", size: 24.8, y: 483)
                + paragraph("Opening text", lines: 3, top: 440)
                + text("1.1. Que es Java", font: "Bold", size: 14.3, y: 390)
                + paragraph("Java text", lines: 5, top: 360),
            head(section: "1.1. QUE ES JAVA")
                + text("1.1.1. final", font: "Bold", size: 12, y: 623)
                + paragraph("Final text", lines: 3, top: 600)
                + text("Software = Programas", size: 14.3, y: 550)
                + paragraph("More text", lines: 3, top: 520)
                + text("1.2. Datos y sus tipos", font: "Bold", size: 14.3, y: 470)
                + paragraph("Data text", lines: 5, top: 440),
            "",
            text("2", font: "Bold", size: 20.7, y: 540)
                + text("Introduccion a la Ingenieria de", font: "Bold", size: 24.8, y: 483)
                + text("Software", font: "Bold", size: 24.8, y: 453)
                + paragraph("Engineering text", lines: 4, top: 410),
            chapterTwoHead
                + text("2.1. Calidad", font: "Bold", size: 14.3, y: 623)
                + paragraph("Quality text", lines: 6, top: 590),
            chapterTwoHead + paragraph("Closing text", lines: 8),
        ]
    }

    /// Writes one level of the outline and returns its first and last references.
    private static func addItems(
        _ nodes: [Node],
        parent: Int,
        pageRefs: [String],
        writer: inout RawPDFWriter
    ) -> (first: String, last: String)? {
        let numbers = nodes.map { _ in writer.reserve() }
        for (index, node) in nodes.enumerated() {
            let children = addItems(
                node.children,
                parent: numbers[index],
                pageRefs: pageRefs,
                writer: &writer
            )
            var entries = [
                "/Title (\(node.title))",
                "/Parent \(parent) 0 R",
                "/Dest [\(pageRefs[node.page]) /XYZ 0 \(pageHeight) null]",
            ]
            if index > 0 { entries.append("/Prev \(numbers[index - 1]) 0 R") }
            if index + 1 < nodes.count { entries.append("/Next \(numbers[index + 1]) 0 R") }
            if let children {
                entries += ["/First \(children.first)", "/Last \(children.last)"]
                entries.append("/Count \(node.children.count)")
            }
            writer.set(numbers[index], "<< \(entries.joined(separator: " ")) >>")
        }
        guard let first = numbers.first, let last = numbers.last else { return nil }
        return ("\(first) 0 R", "\(last) 0 R")
    }

    static func make(hasOutline: Bool) -> Fixture {
        var writer = RawPDFWriter()
        let pagesNumber = writer.reserve()
        let pageRefs = pages().map { content in
            let contents = writer.addStream(content)
            return writer.add(
                """
                << /Type /Page /Parent \(pagesNumber) 0 R /MediaBox [0 0 482 \(Int(pageHeight))] \
                /Contents \(contents) /Resources << /Font << \(fonts()) >> >> >>
                """
            )
        }
        writer.set(
            pagesNumber,
            "<< /Type /Pages /Kids [\(pageRefs.joined(separator: " "))] /Count \(pageRefs.count) >>"
        )
        var catalogEntries = "/Type /Catalog /Pages \(pagesNumber) 0 R"
        if hasOutline {
            let root = writer.reserve()
            let items = addItems(outline, parent: root, pageRefs: pageRefs, writer: &writer)
            writer.set(
                root,
                """
                << /Type /Outlines /First \(items?.first ?? "null") \
                /Last \(items?.last ?? "null") /Count \(outline.count) >>
                """
            )
            catalogEntries += " /Outlines \(root) 0 R /PageMode /UseOutlines"
        }
        let catalog = writer.add("<< \(catalogEntries) >>")
        var truth = GroundTruth()
        truth.pageCount = pageRefs.count
        return Fixture(
            fileName: hasOutline ? "outline-book.pdf" : "unoutlined-book.pdf",
            data: writer.finish(root: catalog),
            truth: truth
        )
    }
}

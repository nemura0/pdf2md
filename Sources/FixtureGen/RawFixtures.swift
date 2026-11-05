import Foundation

/// Writes a PDF object by object, for content CoreGraphics never produces.
struct RawPDFWriter {
    private var objects: [String] = []

    /// Adds an object and returns its reference, such as `5 0 R`.
    @discardableResult
    mutating func add(_ body: String) -> String {
        objects.append(body)
        return "\(objects.count) 0 R"
    }

    /// Adds a stream object. `dictionary` holds entries besides `/Length`.
    @discardableResult
    mutating func addStream(_ content: String, dictionary: String = "") -> String {
        add("<< \(dictionary) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
    }

    /// Reserves an object number now, to be filled by `set` later (for parent references).
    mutating func reserve() -> Int {
        objects.append("null")
        return objects.count
    }

    mutating func set(_ number: Int, _ body: String) {
        objects[number - 1] = body
    }

    func finish(root: String) -> Data {
        var output = "%PDF-1.5\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(output.utf8.count)
            output += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = output.utf8.count
        output += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            output += String(format: "%010d 00000 n \n", offset)
        }
        output += "trailer\n<< /Size \(objects.count + 1) /Root \(root) >>\n"
        output += "startxref\n\(xrefOffset)\n%%EOF\n"
        return Data(output.utf8)
    }
}

/// Fixtures written byte by byte.
enum RawFixtures {
    /// Simple font dictionary shaped like pdfTeX's output, with an unembedded font: on a Mac
    /// without Computer Modern, PDFKit reports all of these as Helvetica.
    private static func simpleFont(
        _ baseFont: String,
        flags: Int,
        width: Int = 500,
        differences: String? = nil
    ) -> String {
        let widths = Array(repeating: String(width), count: 224).joined(separator: " ")
        let encoding =
            differences.map { "<< /Type /Encoding /Differences [ \($0) ] >>" } ?? "/WinAnsiEncoding"
        return """
            << /Type /Font /Subtype /Type1 /BaseFont /\(baseFont) /FirstChar 32 /LastChar 255 \
            /Widths [\(widths)] /Encoding \(encoding) /FontDescriptor << /Type /FontDescriptor \
            /FontName /\(baseFont) /Flags \(flags) /FontBBox [0 -200 1000 800] /ItalicAngle 0 \
            /Ascent 700 /Descent -200 /CapHeight 700 /StemV 80 >> >>
            """
    }

    /// Hex-string code points for a two-byte `Identity-H` show operation.
    private static func hex(_ text: String) -> String {
        "<" + text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined() + ">"
    }

    /// Type0 font with `/W` widths and a `ToUnicode` map, as Office and modern LaTeX produce.
    /// The advance widths are what the scanner needs for the show operation after this one.
    private static func type0Font(writer: inout RawPDFWriter) -> String {
        let cmap = """
            /CIDInit /ProcSet findresource begin
            12 dict begin
            begincmap
            /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
            /CMapName /Adobe-Identity-UCS def
            /CMapType 2 def
            1 begincodespacerange
            <0000> <FFFF>
            endcodespacerange
            1 beginbfrange
            <0020> <00FF> <0020>
            endbfrange
            endcmap
            CMapName currentdict /CMap defineresource pop
            end
            end
            """
        let toUnicode = writer.addStream(cmap)
        let descendant = """
            << /Type /Font /Subtype /CIDFontType2 /BaseFont /ABCDEE+Calibri \
            /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> \
            /DW 500 /W [ 32 [ 250 ] 72 [ 600 500 ] ] /FontDescriptor << /Type /FontDescriptor \
            /FontName /ABCDEE+Calibri /Flags 32 /FontBBox [0 -200 1000 800] /ItalicAngle 0 \
            /Ascent 700 /Descent -200 /CapHeight 700 /StemV 80 >> >>
            """
        return """
            << /Type /Font /Subtype /Type0 /BaseFont /ABCDEE+Calibri /Encoding /Identity-H \
            /DescendantFonts [ \(descendant) ] /ToUnicode \(toUnicode) >>
            """
    }

    /// Raw content streams exercising the operators that CoreGraphics never writes: `TJ` kerns,
    /// `Tc`/`Tw`/`Tz`, `TL`/`T*`/`'`, scaled `cm`, nested Forms, a Form without `/Resources`,
    /// `/Differences` Greek and Type0 text.
    static func pdfTeXStyle() -> Fixture {
        var writer = RawPDFWriter()
        let fonts = """
            /F1 \(simpleFont("ABCDEF+CMR10", flags: 34)) \
            /F2 \(simpleFont(
                "ABCDEF+CMMI10",
                flags: 4,
                differences: "11 /alpha /beta /gamma 60 /less 120 /x /y"
            )) \
            /F3 \(simpleFont("ABCDEF+CMTT10", flags: 35, width: 525)) \
            /F4 \(simpleFont("ABCDEF+CMBX12", flags: 262178, width: 560)) \
            /F5 \(simpleFont("ABCDEF+CMR7", flags: 34, width: 570)) \
            /F6 \(simpleFont("ABCDEF+CMSY10", flags: 4, differences: "20 /lessequal 49 /infinity")) \
            /F7 \(type0Font(writer: &writer))
            """

        let inner = writer.addStream(
            "BT /FI 12 Tf 0 0 Td (Text inside a nested form) Tj ET",
            dictionary: """
                /Type /XObject /Subtype /Form /BBox [0 0 400 100] \
                /Resources << /Font << /FI \(simpleFont("ABCDEF+CMSS10", flags: 32)) >> >>
                """
        )
        let wrapper = writer.addStream(
            "q 1 0 0 1 5 5 cm /Inner Do Q",
            dictionary: """
                /Type /XObject /Subtype /Form /BBox [0 0 420 120] \
                /Resources << /XObject << /Inner \(inner) >> >>
                """
        )
        // No /Resources: the (deprecated but real) case that inherits from the page.
        let bareForm = writer.addStream(
            "BT /F1 10 Tf 0 0 Td (Form without resources) Tj ET",
            dictionary: "/Type /XObject /Subtype /Form /BBox [0 0 300 40]"
        )

        let content = """
            BT
            /F4 14.3462 Tf 72 720 Td [(A)-375(Paper)-375(in)-375(the)-375(pdfT)83(eX)-375(Style)]TJ
            ET
            BT
            /F1 9.9626 Tf 72 690 Td [(T)83(his)-333(line)-333(is)-333(kerned)-333(with)-333(TJ)]TJ
            ET
            BT
            /F1 9.9626 Tf 72 670 Td [(The)-333(value)]TJ
            /F2 9.9626 Tf 70 0 Td [(x)]TJ
            /F5 6.9738 Tf 5.7 3.6 Td [(2)]TJ
            /F1 9.9626 Tf 10 -3.6 Td [(grows,)-333(and)]TJ
            /F2 9.9626 Tf 60 0 Td (\\013) Tj
            /F6 9.9626 Tf 12 0 Td (\\024) Tj
            /F2 9.9626 Tf 12 0 Td (\\014) Tj
            /F1 9.9626 Tf 12 0 Td (holds.) Tj
            ET
            q 1 0 0 1 72 640 cm BT /F3 10 Tf 0 0 Td (int total = 0;) Tj ET Q
            BT /F1 10 Tf 1 0 0 1 72 615 Tm 2 Tc 3 Tw 110 Tz (Spaced words here) Tj 0 Tc 0 Tw 100 Tz ET
            BT /F1 10 Tf 72 590 Td 14 TL (First leading line) Tj T* (Second leading line) Tj (Third leading line) ' ET
            BT /F1 10 Tf 72 530 Td (Mixed) Tj /F2 10 Tf ( x) Tj /F1 10 Tf ( run on one line) Tj ET
            BT /F7 11 Tf 72 505 Td \(hex("Office text")) Tj ( ) Tj /F1 11 Tf 160 0 Td (after type zero) Tj ET
            q 0.5 0 0 0.5 72 400 cm /Wrap Do Q
            q 1 0 0 1 72 370 cm /Bare Do Q
            """
        let contents = writer.addStream(content)

        let pagesNumber = writer.reserve()
        let page = writer.add(
            """
            << /Type /Page /Parent \(pagesNumber) 0 R /MediaBox [0 0 612 792] /Contents \(contents) \
            /Resources << /Font << \(fonts) >> /XObject << /Wrap \(wrapper) /Bare \(bareForm) >> >> >>
            """
        )
        writer.set(pagesNumber, "<< /Type /Pages /Kids [\(page)] /Count 1 >>")
        let catalog = writer.add("<< /Type /Catalog /Pages \(pagesNumber) 0 R >>")

        var truth = GroundTruth()
        truth.title = "A Paper in the pdfTeX Style"
        truth.pageCount = 1
        truth.words =
            "This line is kerned with TJ The value grows, and holds. Spaced words here".split(
                separator: " "
            ).map(String.init)
        truth.orderedPhrases = ["First leading line", "Second leading line", "Third leading line"]
        return Fixture(
            fileName: "pdftex-style.pdf",
            data: writer.finish(root: catalog),
            truth: truth
        )
    }

    /// A page with `/Rotate 90`, whose content is drawn sideways. PDFKit's selection rects stay
    /// in unrotated page space, so geometry must go through the page transform.
    static func rotated() -> Fixture {
        var writer = RawPDFWriter()
        let lines = ["Rotated first line of text", "Rotated second line of text"]
        var content = "BT /F1 12 Tf\n"
        for (index, line) in lines.enumerated() {
            content += "0 1 -1 0 \(100 + index * 20) 100 Tm (\(line)) Tj\n"
        }
        content += "ET"
        let contents = writer.addStream(content)
        let pagesNumber = writer.reserve()
        let page = writer.add(
            """
            << /Type /Page /Parent \(pagesNumber) 0 R /MediaBox [0 0 612 792] /Rotate 90 \
            /Contents \(contents) /Resources << /Font << /F1 \(simpleFont("Helvetica", flags: 32)) >> >> >>
            """
        )
        writer.set(pagesNumber, "<< /Type /Pages /Kids [\(page)] /Count 1 >>")
        let catalog = writer.add("<< /Type /Catalog /Pages \(pagesNumber) 0 R >>")

        var truth = GroundTruth()
        truth.pageCount = 1
        truth.orderedPhrases = lines
        return Fixture(fileName: "rotated.pdf", data: writer.finish(root: catalog), truth: truth)
    }

    /// Structurally valid, with no pages.
    static func zeroPages() -> Fixture {
        var writer = RawPDFWriter()
        let pages = writer.add("<< /Type /Pages /Kids [] /Count 0 >>")
        let catalog = writer.add("<< /Type /Catalog /Pages \(pages) >>")
        return Fixture(fileName: "zero-pages.pdf", data: writer.finish(root: catalog), truth: nil)
    }

    /// Passes the magic-bytes check, and isn't a PDF after that.
    static func corrupt() -> Fixture {
        var bytes = Data("%PDF-1.7\n".utf8)
        var random = SeededGenerator(seed: 13)
        for _ in 0..<4096 {
            bytes.append(UInt8(truncatingIfNeeded: random.next()))
        }
        return Fixture(fileName: "corrupt.pdf", data: bytes, truth: nil)
    }

    /// Named like a PDF, but it is plain text.
    static func notAPDF() -> Fixture {
        Fixture(
            fileName: "not-a-pdf.pdf",
            data: Data("This is a text file with the wrong extension.\n".utf8),
            truth: nil
        )
    }
}

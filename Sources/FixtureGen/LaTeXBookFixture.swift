import Foundation

/// A book shaped like real LuaLaTeX output, written by hand. PDFKit's word rects follow a font's
/// bounding box, and Latin Modern's are tall enough to reach the line above, which CoreGraphics'
/// fixtures never show. It holds what a real book exposed: listings with a line-number gutter set
/// in a small text font, and transparent images whose pixels are identical.
enum LaTeXBookFixture {
    /// Latin Modern's bounding boxes, in thousandths of the font size.
    private static let sansBox = "-420 -281 1431 1167"
    private static let monoBox = "-448 -320 1000 1000"
    private static let pageHeight = 680.0
    private static let textX = 34.0
    private static let bodyLeading = 11.955
    private static let codeLeading = 9.464
    /// `listings` sets leading spaces wider than its glyphs, which are 4.62 wide at this size.
    private static let codeIndentCell = 4.83

    private static func font(_ name: String, flags: Int, box: String, width: Int) -> String {
        let widths = Array(repeating: String(width), count: 224).joined(separator: " ")
        return """
            << /Type /Font /Subtype /Type1 /BaseFont /\(name) /FirstChar 32 /LastChar 255 \
            /Widths [\(widths)] /Encoding /WinAnsiEncoding /FontDescriptor << \
            /Type /FontDescriptor /FontName /\(name) /Flags \(flags) /FontBBox [\(box)] \
            /ItalicAngle 0 /Ascent 1000 /Descent -300 /CapHeight 700 /StemV 80 >> >>
            """
    }

    private static func fonts() -> String {
        """
        /Sans \(font("ABCDEF+LMSans10-Regular", flags: 32, box: sansBox, width: 450)) \
        /Tiny \(font("ABCDEF+LMSans8-Regular", flags: 32, box: sansBox, width: 530)) \
        /Mono \(font("ABCDEF+LMMono8-Regular", flags: 33, box: monoBox, width: 578))
        """
    }

    /// A numbered listing. `nil` code is a blank line, which still has its number.
    private static func listing(_ lines: [(indent: Int, code: String?)], top: Double) -> String {
        var content = ""
        for (offset, line) in lines.enumerated() {
            let y = top - Double(offset) * codeLeading
            let number = offset + 1
            let numberX = textX - 7.6 - (number >= 10 ? 2.65 : 0)
            content += "BT /Tiny 4.981 Tf \(numberX) \(y) Td (\(number)) Tj ET\n"
            guard let code = line.code else { continue }
            let x = textX + Double(line.indent) * codeIndentCell
            content += "BT /Mono 7.97 Tf \(x) \(y) Td (\(escape(code))) Tj ET\n"
        }
        return content
    }

    private static func body(_ lines: [String], top: Double) -> String {
        lines.enumerated().map { offset, line in
            "BT /Sans 9.963 Tf \(textX) \(top - Double(offset) * bodyLeading) Td (\(escape(line))) Tj ET\n"
        }.joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacing("\\", with: "\\\\").replacing("(", with: "\\(").replacing(")", with: "\\)")
    }

    /// Black pixels, with the drawing held entirely in the soft mask, as drawing tools export a
    /// diagram on a transparent background. Only the mask tells two of these apart.
    private static func transparentImage(writer: inout RawPDFWriter, filledRows: Int) -> String {
        let side = 8
        let mask = (0..<side * side).map { $0 / side < filledRows ? "FF" : "00" }.joined()
        let maskStream = writer.addStream(
            mask + ">",
            dictionary: """
                /Type /XObject /Subtype /Image /Width \(side) /Height \(side) \
                /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /ASCIIHexDecode
                """
        )
        let pixels = String(repeating: "000000", count: side * side)
        return writer.addStream(
            pixels + ">",
            dictionary: """
                /Type /XObject /Subtype /Image /Width \(side) /Height \(side) \
                /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode \
                /SMask \(maskStream)
                """
        )
    }

    static func make() -> Fixture {
        var writer = RawPDFWriter()
        let pagesNumber = writer.reserve()
        var kids: [String] = []

        func addPage(_ content: String, xObjects: String = "", writer: inout RawPDFWriter) {
            let contents = writer.addStream(content)
            kids.append(
                writer.add(
                    """
                    << /Type /Page /Parent \(pagesNumber) 0 R /MediaBox [0 0 482 \(Int(pageHeight))] \
                    /Contents \(contents) /Resources << /Font << \(fonts()) >> \
                    /XObject << \(xObjects) >> >> >>
                    """
                )
            )
        }

        addPage(
            body(["Por ejemplo:"], top: 620)
                + listing(
                    [
                        (0, "public class Ejemplo1"),
                        (0, "{"),
                        (4, "public static void main(String[] args)"),
                        (4, "{"),
                        (8, "for(int i=0;i<5;i++) {"),
                        (12, "System.out.println(i);"),
                        (8, "}"),
                        (8, nil),
                        (8, "int total = 0;"),
                        (4, "}"),
                        (0, "}"),
                    ],
                    top: 604
                )
                + body(["Este ciclo repetira 5 veces el print de la linea 6."], top: 480),
            writer: &writer
        )

        let firstImage = transparentImage(writer: &writer, filledRows: 2)
        let secondImage = transparentImage(writer: &writer, filledRows: 6)
        let draw = { (name: String) in "q 200 0 0 120 100 400 cm /\(name) Do Q\n" }
        addPage(
            body(["Primera figura."], top: 620) + draw("A"),
            xObjects: "/A \(firstImage)",
            writer: &writer
        )
        addPage(
            body(["Segunda figura."], top: 620) + draw("B"),
            xObjects: "/B \(secondImage)",
            writer: &writer
        )

        writer.set(
            pagesNumber,
            "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(kids.count) >>"
        )
        let catalog = writer.add("<< /Type /Catalog /Pages \(pagesNumber) 0 R >>")

        var truth = GroundTruth()
        truth.pageCount = kids.count
        truth.codeLines = [
            " 1 public class Ejemplo1",
            " 2 {",
            " 3     public static void main(String[] args)",
            " 4     {",
            " 5         for(int i=0;i<5;i++) {",
            " 6             System.out.println(i);",
            " 7         }",
            " 8",
            " 9         int total = 0;",
            "10     }",
            "11 }",
        ]
        truth.keptFigures = 2
        return Fixture(
            fileName: "latex-book.pdf",
            data: writer.finish(root: catalog),
            truth: truth
        )
    }
}

import Foundation

/// What a real LaTeX book draws instead of typesetting: TikZ diagrams with no image or form around
/// them, tables as grids of rules cut at each row, listings side by side, footnotes under a short
/// rule, and check marks from a symbol font that has no text at all.
enum DrawingBookFixture {
    private static let pageHeight = 680.0
    private static let textX = 34.0
    private static let bodyLeading = 12.0
    private static let codeLeading = 9.5
    private static let scriptRise = 3.6
    /// In a table's rows, this cell is a check mark from the symbol font, code 34.
    private static let checkMark = "(check)"
    /// In a listing, lines left out, starting at the code's indent with no space drawn before it.
    private static let elision = "..."
    private static let elisionIndent = 18.4

    private static func font(_ name: String, flags: Int, width: Int, encoded: Bool = true) -> String
    {
        let widths = Array(repeating: String(width), count: 224).joined(separator: " ")
        let encoding = encoded ? "/Encoding /WinAnsiEncoding" : ""
        return """
            << /Type /Font /Subtype /Type1 /BaseFont /\(name) /FirstChar 32 /LastChar 255 \
            /Widths [\(widths)] \(encoding) /FontDescriptor << \
            /Type /FontDescriptor /FontName /\(name) /Flags \(flags) \
            /FontBBox [-420 -281 1431 1167] /ItalicAngle 0 /Ascent 850 /Descent -230 \
            /CapHeight 700 /StemV 80 >> >>
            """
    }

    private static func fonts() -> String {
        """
        /Sans \(font("ABCDEF+LMSans10-Regular", flags: 32, width: 450)) \
        /Bold \(font("ABCDEF+LMSans10-Bold", flags: 262176, width: 500)) \
        /Tiny \(font("ABCDEF+LMSans8-Regular", flags: 32, width: 530)) \
        /Mono \(font("ABCDEF+LMMono8-Regular", flags: 33, width: 578)) \
        /Ital \(font("ABCDEF+LMSans10-Oblique", flags: 96, width: 450)) \
        /Math \(font("ABCDEF+LMMathItalic10-Regular", flags: 4, width: 450)) \
        /Sym \(font("ABCDEF+bbding", flags: 4, width: 1000, encoded: false))
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

    private static func body(_ lines: [String], top: Double) -> String {
        lines.enumerated().map { offset, line in
            text(line, y: top - Double(offset) * bodyLeading)
        }.joined()
    }

    private static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> String {
        "q 0.4 w \(x1) \(y1) m \(x2) \(y2) l S Q\n"
    }

    /// A UML class: a filled box, its outline, and a rule under each compartment.
    private static func classBox(
        x: Double,
        y: Double,
        title: String,
        members: [String]
    ) -> String {
        let width = 130.0
        let height = 30.0 + Double(members.count) * 12
        let top = y + height
        var content = "q 0.9 0.9 0.6 rg \(x) \(y) \(width) \(height) re f Q\n"
        content += "q 0.4 w \(x) \(y) \(width) \(height) re S Q\n"
        content += line(x, top - 18, x + width, top - 18)
        content += text(title, font: "Bold", size: 9, x: x + 40, y: top - 13)
        for (offset, member) in members.enumerated() {
            content += text(member, size: 9, x: x + 6, y: top - 30 - Double(offset) * 12)
        }
        return content
    }

    /// Two classes joined by an arrow, with a line curving round below them.
    private static func classDiagram(y: Double) -> String {
        classBox(x: 80, y: y, title: "Persona", members: ["-rut:String", "+getRut():String"])
            + classBox(x: 270, y: y, title: "Celular", members: ["-modelo:String"])
            + line(210, y + 20, 270, y + 20)
            + "q 265 \(y + 17) m 270 \(y + 20) l 265 \(y + 23) l h f Q\n"
            + text("compra", size: 8, x: 222, y: y + 24)
            // A caption in a box of its own, close to the drawing without touching it.
            + "q 0.4 w 300 \(y + 62) 90 18 re S Q\n"
            + text("Una venta", size: 9, x: 310, y: y + 67)
            // Drawn twice in the same spot, which is how some books fake a bold font.
            + text("registrado", size: 9, x: 240, y: y - 34)
            + text("registrado", size: 9, x: 240, y: y - 34)
            + "q 0.4 w 140 \(y) m 140 \(y - 22) 330 \(y - 22) 330 \(y) c S Q\n"
            // An arrow stopping short of a box, and the variable it starts from, set apart.
            + "q 0.4 w 48 \(y + 18) m 52 \(y + 34) 64 \(y + 34) 70 \(y + 28) c S Q\n"
            + text("prod", size: 9, x: 26, y: y + 8)
    }

    /// A table the way LaTeX's `tabular` draws it: a rule per row, and its column lines cut at
    /// every row, with small gaps at the crossings.
    private static func gridTable(xs: [Double], rows: [[String]], top: Double) -> String {
        let rowHeight = 12.2
        var content = ""
        for (offset, row) in rows.enumerated() {
            let y = top - Double(offset) * rowHeight
            content += line(xs[0], y, xs[xs.count - 1], y)
            for x in xs { content += line(x, y - rowHeight + 0.2, x, y - 0.2) }
            for (column, cell) in row.enumerated() where column + 1 < xs.count {
                content +=
                    cell == checkMark
                    ? text("\"", font: "Sym", x: xs[column] + 20, y: y - 9)
                    : text(cell, x: xs[column] + 5, y: y - 9)
            }
        }
        let bottom = top - Double(rows.count) * rowHeight
        return content + line(xs[0], bottom, xs[xs.count - 1], bottom)
    }

    private static func listing(_ lines: [String?], x: Double, top: Double) -> String {
        lines.enumerated().map { offset, code in
            let y = top - Double(offset) * codeLeading
            let number = text("\(offset + 1)", font: "Tiny", size: 4.981, x: x - 7.6, y: y)
            guard let code else { return number }
            let indent = code == elision ? elisionIndent : 0
            return number + text(code, font: "Mono", size: 7.97, x: x + indent, y: y)
        }.joined()
    }

    private static func marker(_ mark: String, x: Double, y: Double) -> String {
        text(mark, size: 6.974, x: x, y: y + scriptRise)
    }

    /// LaTeX's footnote rule, and its notes in a smaller size.
    private static func notes(_ notes: [(mark: String, text: String)], ruleY: Double) -> String {
        var content = line(textX, ruleY, textX + 170, ruleY)
        for (offset, note) in notes.enumerated() {
            let y = ruleY - 10 - Double(offset) * 9.6
            content += text(note.mark, size: 5.978, x: textX + 10.7, y: y + 2.8)
            content += text(note.text, size: 7.97, x: textX + 14.1, y: y)
        }
        return content
    }

    private static func diagramPage() -> String {
        text("Clases y objetos", font: "Bold", size: 14.3, y: 630)
            + body(["Una clase se dibuja como una caja con sus atributos:"], top: 605)
            + classDiagram(y: 510)
            + body(["Despues del diagrama sigue el texto normal de la pagina."], top: 465)
            + "q 0.9 g 100 438 30 11 re f Q\nq 0.9 g 140 426 30 11 re f Q\nq 0.9 g 100 414 30 11 re f Q\n"
            + body(
                [
                    "Este parrafo tiene codigo sombreado en varias de sus lineas pero no es un dibujo",
                    "porque sus lineas salen muy lejos de cada uno de esos rectangulos pequenos que",
                    "hay detras de algunas palabras y eso es propio de un parrafo de texto corriente.",
                ],
                top: 440
            )
            + gridTable(
                xs: [80, 180, 260, 400],
                rows: [
                    ["Nombre", "Tamano", "Descripcion"],
                    ["byte", "1 byte", "Un entero corto"],
                    ["double", "8 bytes", "Un decimal doble"],
                ],
                top: 395
            )
            + body(["Un entorno de desarrollo"], top: 330)
            + marker("1,", x: 142, y: 330)
            + text("es la herramienta que usaremos.", x: 155, y: 330)
            + body(["El siguiente es el compilador"], top: 318)
            + marker("2", x: 164.5, y: 318)
            + text(", que traduce el codigo.", x: 170, y: 318)
            + body(
                ["Este otro parrafo empieza en esta pagina y no termina en ella porque sigue en"],
                top: 294
            )
            + notes(
                [("1", "IDE: entorno integrado de desarrollo"), ("2", "Se llama javac")],
                ruleY: 60
            )
    }

    private static func listingsPage() -> String {
        body(["la siguiente, donde se acaba la frase."], top: 630)
            + body(["Lo mismo en los dos lenguajes:"], top: 605)
            + listing(["x = 15", nil, "if x < 30:", "  print(x)"], x: textX, top: 580)
            + listing(
                [
                    "public class Main", "{", "    int x = 15;", "    void run()", "    {",
                    "        print(x);", "    }", "}",
                ],
                x: 200,
                top: 580
            )
            + body(["Y una tabla de marcas:"], top: 480)
            + gridTable(
                xs: [80, 180, 260],
                rows: [["Nivel", "Clase"], ["public", checkMark], ["private", checkMark]],
                top: 465
            )
    }

    /// An exercise's letter is italic and its parenthesis isn't, so PDFKit has them as two words,
    /// and an `f` leans far enough to get a space before it.
    private static func letteredItem(
        _ letter: String,
        _ gap: Double,
        _ text: String,
        y: Double
    ) -> String {
        Self.text(letter, font: "Ital", x: 60, y: y)
            + Self.text("\\)", x: 64.5 + gap, y: y)
            + Self.text(text, x: 74, y: y)
    }

    private static func exercisesPage() -> String {
        text("Ejercicios", font: "Bold", size: 14.3, y: 622)
            + listing(
                ["public class Main", "{", "    void run()", "    {", elision, "    }", "}"],
                x: textX,
                top: 605
            )
            // Math italic leans past its own width, and PDFKit reads that as a word space.
            + text("CostoT", font: "Math", x: 150, y: 520)
            + text("otal", font: "Math", x: 178.3, y: 520)
            + text("=", x: 198, y: 520)
            + text("P", font: "Math", x: 210, y: 520)
            + text("recio", font: "Math", x: 216, y: 520)
            + letteredItem("a", 0, "Asigna una variable con cero", y: 490)
            + letteredItem("f", 2, "Si es menor entonces asigna otra", y: 478)
            + letteredItem("g", 0, "Si es igual termina el proceso", y: 466)
            + body(
                [
                    "1. Revisa el codigo fuente de la clase para que veas como esta hecho aquel metodo"
                ],
                top: 440
            )
            + text("toString().", font: "Mono", size: 9.963, x: 47, y: 428)
            + body(["Y el texto sigue despues de todo esto."], top: 400)
            + body(["Para mas informacion se puede visitar"], top: 370)
            + text("https://example.org/docs/page.html", font: "Mono", x: 63, y: 341)
    }

    static func make() -> Fixture {
        var writer = RawPDFWriter()
        let pagesNumber = writer.reserve()
        let contents = [
            text("Libro de Dibujos", font: "Bold", size: 24.8, x: 120, y: 500)
                + body(["Un libro corto para probar lo que se dibuja."], top: 450),
            diagramPage(),
            listingsPage(),
            exercisesPage(),
        ]
        let kids = contents.map { content in
            let stream = writer.addStream(content)
            return writer.add(
                """
                << /Type /Page /Parent \(pagesNumber) 0 R /MediaBox [0 0 482 \(Int(pageHeight))] \
                /Contents \(stream) /Resources << /Font << \(fonts()) >> >> >>
                """
            )
        }
        writer.set(
            pagesNumber,
            "<< /Type /Pages /Kids [\(kids.joined(separator: " "))] /Count \(kids.count) >>"
        )
        let catalog = writer.add("<< /Type /Catalog /Pages \(pagesNumber) 0 R >>")
        var truth = GroundTruth()
        truth.pageCount = kids.count
        return Fixture(
            fileName: "drawing-book.pdf",
            data: writer.finish(root: catalog),
            truth: truth
        )
    }
}

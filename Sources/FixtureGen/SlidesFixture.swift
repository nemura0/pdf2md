import CoreGraphics
import Foundation

/// Lays out 16:9 slides with a repeated logo and footer on each.
final class SlideWriter {
    let canvas: PDFCanvas
    var truth = GroundTruth()
    private let logo: CGImage
    private let footer: String
    private var y: CGFloat = 0

    private let left: CGFloat = 60
    private let right: CGFloat = 900

    init(logo: CGImage, footer: String, title: String? = nil) throws {
        canvas = try PDFCanvas(pageSize: CGSize(width: 960, height: 540), title: title)
        self.logo = logo
        self.footer = footer
    }

    func begin(title: String?, titleSize: CGFloat = 30) {
        canvas.beginPage()
        canvas.image(logo, in: CGRect(x: 840, y: 470, width: 80, height: 40))
        let footerText = "\(footer)   \(canvas.pageCount)"
        canvas.text(footerText, font: .sans, size: 10, x: left, y: 22)
        truth.forbiddenLines.append(footerText)
        y = 470
        if let title {
            canvas.text(title, font: .sansBold, size: titleSize, x: left, y: y)
            truth.headings.append(.init(level: 2, text: title))
            y -= 48
        }
    }

    func end() {
        canvas.endPage()
    }

    func bullets(_ items: [(depth: Int, text: String)]) {
        for item in items {
            let size: CGFloat = item.depth == 0 ? 20 : 17
            let markerX = left + 10 + CGFloat(item.depth) * 30
            canvas.text(item.depth == 0 ? "•" : "–", font: .sans, size: size, x: markerX, y: y)
            canvas.text(item.text, font: .sans, size: size, x: markerX + 22, y: y)
            truth.words += item.text.split(separator: " ").map(String.init)
            y -= size * 1.6
        }
    }

    func paragraph(_ text: String) {
        canvas.text(text, font: .sans, size: 18, x: left, y: y)
        truth.words += text.split(separator: " ").map(String.init)
        y -= 30
    }

    func code(_ lines: [String]) {
        for line in lines {
            canvas.text(line, font: .mono, size: 15, x: left + 20, y: y)
            y -= 20
        }
        y -= 10
        truth.codeLines += lines
    }

    func figure(_ image: CGImage, width: CGFloat, height: CGFloat) {
        canvas.image(image, in: CGRect(x: left + 90, y: y - height, width: width, height: height))
        y -= height + 16
        truth.keptFigures += 1
    }

    func table(_ rows: [[String]], columnWidths: [CGFloat]) {
        let rowHeight: CGFloat = 34
        let width = columnWidths.reduce(0, +)
        let height = CGFloat(rows.count) * rowHeight
        let top = y
        for row in 0...rows.count {
            let lineY = top - CGFloat(row) * rowHeight
            canvas.rule(from: CGPoint(x: left, y: lineY), to: CGPoint(x: left + width, y: lineY))
        }
        var columnX = left
        for columnWidth in columnWidths + [0] {
            canvas.rule(from: CGPoint(x: columnX, y: top), to: CGPoint(x: columnX, y: top - height))
            columnX += columnWidth
        }
        for (rowIndex, row) in rows.enumerated() {
            var cellX = left
            for (columnIndex, cell) in row.enumerated() {
                let font: FixtureFont = rowIndex == 0 ? .sansBold : .sans
                let baseline = top - CGFloat(rowIndex) * rowHeight - 23
                canvas.text(cell, font: font, size: 16, x: cellX + 8, y: baseline)
                cellX += columnWidths[columnIndex]
            }
        }
        y = top - height - 20
        truth.tables.append(rows)
    }
}

enum SlidesFixture {
    /// Has no useful metadata title, so the title must come from the largest text on page 1.
    static let deckTitle = "Programación Orientada a Objetos"

    static func make() throws -> Fixture {
        let slides = try SlideWriter(
            logo: try FixtureImages.logo(),
            footer: "Universidad Ejemplo, curso 2026",
            title: "PowerPoint Presentation"
        )
        slides.truth.title = deckTitle

        // A cover has the deck title, which stays the document's only `#`.
        slides.canvas.beginPage()
        slides.canvas.image(
            try FixtureImages.logo(),
            in: CGRect(x: 840, y: 470, width: 80, height: 40)
        )
        slides.canvas.text(deckTitle, font: .sansBold, size: 42, x: 60, y: 300)
        slides.canvas.text("Clase 3: clases y objetos", font: .sans, size: 22, x: 60, y: 255)
        let coverFooter = "Universidad Ejemplo, curso 2026   1"
        slides.canvas.text(coverFooter, font: .sans, size: 10, x: 60, y: 22)
        slides.truth.forbiddenLines.append(coverFooter)
        slides.truth.words += ["Clase", "3:", "clases", "y", "objetos"]
        slides.end()

        slides.begin(title: "Objetivos de la clase")
        slides.bullets([
            (0, "Comprender qué es una clase"),
            (1, "Atributos y métodos"),
            (1, "Encapsulación básica"),
            (0, "Crear objetos en Java y Python"),
            (0, "Leer código con atención"),
        ])
        slides.end()

        slides.begin(title: "Una clase en Java")
        slides.paragraph("Cada objeto guarda su propio estado:")
        slides.code([
            "public class Punto {",
            "    private double x;",
            "    public double getX() {",
            "        return x;",
            "    }",
            "}",
        ])
        slides.end()

        slides.begin(title: "Lo mismo en Python")
        slides.code([
            "class Punto:",
            "    def __init__(self, x):",
            "        self.x = x",
            "",
            "    def get_x(self):",
            "        return self.x",
        ])
        slides.end()

        slides.begin(title: "Resultados del curso")
        slides.paragraph("Promedios por unidad en el semestre anterior.")
        slides.figure(
            try FixtureImages.barChart(values: [55, 70, 62, 88, 95, 40]),
            width: 520,
            height: 260
        )
        slides.end()

        slides.begin(title: "Evaluaciones")
        slides.table(
            [
                ["Evaluación", "Semana", "Ponderación"],
                ["Prueba 1", "5", "30%"],
                ["Prueba 2", "10", "30%"],
                ["Proyecto final", "15", "40%"],
            ],
            columnWidths: [320, 150, 200]
        )
        slides.paragraph("Se aprueba con nota 4,0 en cada una.")
        slides.end()

        slides.begin(title: "Resumen")
        slides.bullets([
            (0, "Una clase define estado y comportamiento"),
            (0, "Los objetos son instancias de una clase"),
            (0, "La próxima clase veremos herencia"),
        ])
        slides.end()

        slides.truth.pageCount = slides.canvas.pageCount
        return Fixture(
            fileName: "slides.pdf",
            data: slides.canvas.finish(label: "slides"),
            truth: slides.truth
        )
    }
}

enum BenchSlidesFixture {
    /// A long deck: unique text on each slide, a unique chart on every fifth, and the logo
    /// repeated everywhere. Used to check memory and repeated-image handling at scale.
    static func make(name: String, slides count: Int) throws -> Fixture {
        var random = SeededGenerator(seed: 400)
        let logo = try FixtureImages.logo()
        let slides = try SlideWriter(logo: logo, footer: "Benchmark deck")
        for index in 1...count {
            slides.begin(title: "Slide topic number \(index)")
            let items = (0..<4).map { _ in
                (
                    depth: random.int(in: 0...1),
                    text: LongDocumentFixture.sentence(&random, words: 7)
                )
            }
            slides.bullets(items)
            if index.isMultiple(of: 5) {
                let values = (0..<6).map { _ in random.int(in: 10...95) }
                let chart = try FixtureImages.barChart(
                    values: values,
                    seedColor: CGFloat(index % 7) / 10
                )
                slides.figure(chart, width: 360, height: 180)
            }
            slides.end()
        }
        return Fixture(fileName: name, data: slides.canvas.finish(label: name), truth: nil)
    }
}

enum EmojiNameFixture {
    /// The name is the point: spaces, an em dash, accents and an emoji.
    static let fileName = "Clase 03 — Programación 🚀.pdf"

    static func make() throws -> Fixture {
        let canvas = try PDFCanvas(pageSize: CGSize(width: 612, height: 792))
        var truth = GroundTruth()
        truth.title = "Introducción a la programación"

        canvas.beginPage()
        canvas.text(truth.title, font: .sansBold, size: 22, x: 72, y: 700)
        let paragraph = [
            "Un programa es una secuencia de instrucciones que el computador sigue al pie de la",
            "letra. Esta clase revisa variables, condiciones y ciclos con ejemplos en español.",
        ]
        for (index, line) in paragraph.enumerated() {
            canvas.text(line, font: .body, size: 11, x: 72, y: 660 - CGFloat(index) * 15)
            truth.words += line.split(separator: " ").map(String.init)
        }
        canvas.endPage()

        canvas.beginPage()
        canvas.text("Variables y tipos", font: .sansBold, size: 15, x: 72, y: 700)
        truth.headings.append(.init(level: 2, text: "Variables y tipos"))
        let second = "Una variable guarda un valor. ¿Qué tamaño tiene? Depende del tipo elegido."
        canvas.text(second, font: .body, size: 11, x: 72, y: 670)
        truth.words += second.split(separator: " ").map(String.init)
        canvas.endPage()

        truth.pageCount = 2
        return Fixture(fileName: fileName, data: canvas.finish(label: "emoji"), truth: truth)
    }
}

enum EncryptedFixture {
    /// Needs a password to open, so it must be skipped with a reason. CoreGraphics salts the
    /// file and `/ID` feeds the key, so this is the one fixture that isn't byte-deterministic.
    static func make() throws -> Fixture {
        let canvas = try PDFCanvas(
            pageSize: CGSize(width: 612, height: 792),
            extraInfo: [
                kCGPDFContextUserPassword: "open-sesame",
                kCGPDFContextOwnerPassword: "owner-sesame",
            ]
        )
        canvas.beginPage()
        canvas.text("This text is locked.", font: .body, size: 12, x: 72, y: 700)
        canvas.endPage()
        return Fixture(
            fileName: "encrypted.pdf",
            data: canvas.finish(label: "encrypted", normalize: false),
            truth: nil
        )
    }
}

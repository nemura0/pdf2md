import CoreGraphics
import Foundation
import ImageIO
import PDFKit

/// Image-only pages, as a scanner would produce: no text layer at all.
enum ScannedFixture {
    private static let scale: CGFloat = 2
    private static let jpegQuality = 0.8

    /// A scanned copy of the book. Same ground truth, tested structurally through OCR.
    static func make(from book: (data: Data, truth: GroundTruth)) throws -> Fixture {
        let pdf = try scan(pdf: book.data, label: "scanned", pageLimit: nil)
        var truth = book.truth
        // Vision can't be held to exact math, code spacing or margin text. Tests check words
        // and structure, not these.
        truth.mathFragments = []
        truth.codeLines = []
        truth.forbiddenLines = []
        return Fixture(fileName: "scanned.pdf", data: pdf, truth: truth)
    }

    static func makeLong(name: String, pages: Int) throws -> Fixture {
        let source = try LongDocumentFixture.make(name: "source", pages: pages)
        return Fixture(
            fileName: name,
            data: try scan(pdf: source.data, label: name, pageLimit: nil),
            truth: nil
        )
    }

    private static func scan(pdf: Data, label: String, pageLimit: Int?) throws -> Data {
        guard let source = PDFDocument(data: pdf) else {
            throw FixtureError.renderFailed("the source of \(label)")
        }
        let canvas = try PDFCanvas(pageSize: CGSize(width: 612, height: 792))
        let pageCount = min(source.pageCount, pageLimit ?? source.pageCount)
        for index in 0..<pageCount {
            try autoreleasepool {
                guard let page = source.page(at: index) else {
                    throw FixtureError.renderFailed("page \(index) of \(label)")
                }
                let image = try jpegImage(of: page)
                canvas.beginPage()
                canvas.image(image, in: CGRect(x: 0, y: 0, width: 612, height: 792))
                canvas.endPage()
            }
        }
        return canvas.finish(label: label)
    }

    private static func jpegImage(of page: PDFPage) throws -> CGImage {
        let bitmap = try FixtureImages.makeBitmap(
            width: Int(612 * scale),
            height: Int(792 * scale)
        ) { context in
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
        let encoded = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                encoded,
                "public.jpeg" as CFString,
                1,
                nil
            )
        else { throw FixtureError.renderFailed("a JPEG") }
        let options = [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, bitmap, options)
        guard CGImageDestinationFinalize(destination),
            let provider = CGDataProvider(data: encoded),
            let jpeg = CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else { throw FixtureError.renderFailed("a JPEG") }
        return jpeg
    }
}

/// A long, regular text document: running margins, periodic headings, lists and code.
enum LongDocumentFixture {
    private static let vocabulary = [
        "system", "memory", "process", "value", "result", "method", "table", "index", "record",
        "structure", "function", "program", "state", "input", "output", "number", "pattern",
        "module", "layer", "signal", "buffer", "stream", "request", "response", "model", "data",
        "the", "of", "and", "to", "in", "for", "with", "that", "each", "every", "when", "while",
        "reads", "writes", "keeps", "builds", "checks", "returns", "stores", "moves", "joins",
    ]

    static func sentence(_ random: inout SeededGenerator, words: Int) -> String {
        var parts = (0..<words).map { _ in random.pick(vocabulary) }
        parts[0] = parts[0].capitalized
        return parts.joined(separator: " ") + "."
    }

    static func make(name: String, pages: Int) throws -> Fixture {
        var random = SeededGenerator(seed: 700)
        let canvas = try PDFCanvas(
            pageSize: CGSize(width: 612, height: 792),
            title: "Long Technical Manual"
        )
        for page in 1...pages {
            autoreleasepool {
                canvas.beginPage()
                drawPage(page, on: canvas, random: &random)
                canvas.endPage()
            }
        }
        var truth = GroundTruth()
        truth.title = "Long Technical Manual"
        truth.pageCount = pages
        return Fixture(fileName: name, data: canvas.finish(label: name), truth: truth)
    }

    private static func drawPage(
        _ page: Int,
        on canvas: PDFCanvas,
        random: inout SeededGenerator
    ) {
        let header = page.isMultiple(of: 2) ? "\(page)   Manual" : "Manual   \(page)"
        canvas.text(header, font: .bodyItalic, size: 9, x: 72, y: 750)
        canvas.text("Page \(page)", font: .body, size: 8, x: 290, y: 40)

        var y: CGFloat = 712
        if page.isMultiple(of: 12) {
            canvas.text("Part \(page / 12)", font: .sansBold, size: 17, x: 72, y: y)
            y -= 30
        } else if page.isMultiple(of: 4) {
            canvas.text("Section \(page / 4)", font: .sansBold, size: 13, x: 72, y: y)
            y -= 24
        }
        let lineCount = 40
        for lineIndex in 0..<lineCount {
            guard y > 80 else { break }
            if page.isMultiple(of: 9), lineIndex == 10 {
                y = drawCode(on: canvas, y: y)
                continue
            }
            if page.isMultiple(of: 7), (12..<16).contains(lineIndex) {
                canvas.text("•", font: .body, size: 10.5, x: 86, y: y)
                let item = sentence(&random, words: 8)
                canvas.text(item, font: .body, size: 10.5, x: 100, y: y)
                y -= 14
                continue
            }
            let line = sentence(&random, words: 13)
            canvas.text(line, font: .body, size: 10.5, x: 72, y: y)
            y -= 14
        }
    }

    private static func drawCode(on canvas: PDFCanvas, y start: CGFloat) -> CGFloat {
        let lines = ["int total = 0;", "for (int i = 0; i < n; i++) {", "    total += i;", "}"]
        var y = start
        for line in lines {
            canvas.text(line, font: .mono, size: 9, x: 82, y: y)
            y -= 12
        }
        return y - 6
    }
}

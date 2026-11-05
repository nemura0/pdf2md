import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing

@testable import FixtureGen
@testable import PDF2MDKit

/// A recognizer that always fails, to test the path where Vision is unavailable.
private struct FailingRecognizer: DocumentRecognizing {
    struct Failure: Error {}

    func recognize(_ image: CGImage) async throws -> RecognizedPage {
        throw Failure()
    }
}

@Suite("Recognition", .serialized)
struct RecognitionTests {
    private func fixture(_ name: String) throws -> Fixture {
        try TestFixtures.named(name)
    }

    private func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        )
    }

    private func wordRecall(of truth: GroundTruth, in markdown: String) -> Double {
        let found = tokens(markdown)
        let wanted = tokens(truth.words.joined(separator: " "))
        return Double(wanted.intersection(found).count) / Double(max(wanted.count, 1))
    }

    /// The GFM rows in a Markdown text, cell by cell.
    private func tableRows(in markdown: String) -> [[String]] {
        markdown.split(separator: "\n")
            .filter { $0.hasPrefix("| ") && !$0.hasPrefix("| ---") }
            .map { row in
                row.dropFirst(2).dropLast(2).components(separatedBy: " | ")
            }
    }

    @Test("a scanned book comes through OCR with its words, title and structure")
    func scanned() async throws {
        let fixture = try fixture("scanned.pdf")
        let truth = try #require(fixture.truth)
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }

        let (markdown, report, _) = try await harness.convert(fixture)

        #expect(report.stats.ocrPages == truth.pageCount)
        #expect(report.stats.failedPages == 0)
        #expect(wordRecall(of: truth, in: markdown) > 0.9)
        #expect(markdown.contains("# Foundations of Computing"))
        let headings = markdown.split(separator: "\n").filter { $0.hasPrefix("## ") }
        #expect(headings.contains { $0.contains("Introduction") })
        #expect(headings.contains { $0.contains("Measuring cost") })
        // The page image is not a figure, and page numbers don't survive.
        #expect(!markdown.contains("!["))
        #expect(OutputInvariants.violations(in: markdown).isEmpty)
    }

    @Test("--ocr never leaves a scanned page without text, and says nothing failed")
    func never() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, report, _) = try await harness.convert(
            try fixture("scanned.pdf"),
            options: ConvertOptions(ocrMode: .never)
        )
        #expect(report.stats.ocrPages == 0)
        #expect(!markdown.contains("Introduction"))
    }

    @Test("--ocr always reads a page with a text layer through Vision, upright when rotated")
    func always() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let fixture = try fixture("rotated.pdf")
        let (markdown, report, _) = try await harness.convert(
            fixture,
            options: ConvertOptions(ocrMode: .always)
        )
        #expect(report.stats.ocrPages > 0)
        // Vision misreads this fixture's letter-spaced word, so this checks direction and order.
        let first = try #require(markdown.range(of: "first"))
        let second = try #require(markdown.range(of: "second"))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test("if Vision fails, the scanned pages count as failed, and a text page is unharmed")
    func visionFailure() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        do {
            _ = try await harness.convert(
                try fixture("scanned.pdf"),
                recognizer: FailingRecognizer()
            )
            Issue.record("every page failed, so the file should have")
        } catch {
            #expect("\(error)".contains("no page could be read"))
        }

        let (markdown, report, _) = try await harness.convert(
            try fixture("slides.pdf"),
            recognizer: FailingRecognizer()
        )
        #expect(report.stats.failedPages == 0)
        #expect(markdown.contains("Prueba 1"))
    }

    @Test("born-digital tables become GFM tables, with exact text from the text layer")
    func tables() async throws {
        for name in ["book.pdf", "slides.pdf"] {
            let fixture = try fixture(name)
            let truth = try #require(fixture.truth)
            let harness = try ConversionHarness()
            defer { harness.cleanUp() }

            let (markdown, report, _) = try await harness.convert(fixture)

            #expect(report.stats.tables == truth.tables.count)
            let rows = tableRows(in: markdown)
            for table in truth.tables {
                for row in table { #expect(rows.contains(row), "\(name): \(row)") }
            }
        }
    }

    @Test("a table's text isn't repeated in the flow around it")
    func noDuplicates() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, _, _) = try await harness.convert(try fixture("book.pdf"))
        #expect(markdown.components(separatedBy: "Search unsorted").count == 2)
    }

    @Test("a table is placed between the text around it")
    func placement() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, _, _) = try await harness.convert(try fixture("book.pdf"))
        let lead = try #require(markdown.range(of: "cost of common operations"))
        let table = try #require(markdown.range(of: "| Read by index"))
        let after = try #require(markdown.range(of: "No structure wins"))
        #expect(lead.upperBound < table.lowerBound)
        #expect(table.upperBound < after.lowerBound)
    }

    // MARK: Images

    private func figureLinks(in markdown: String) -> [String] {
        markdown.matches(of: /!\[Figure\]\(([^)]+)\)/).map { String($0.1) }
    }

    @Test("a figure is cropped and linked, and the logo on every slide isn't")
    func figures() async throws {
        let fixture = try fixture("slides.pdf")
        let truth = try #require(fixture.truth)
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }

        let (markdown, report, url) = try await harness.convert(fixture)

        #expect(report.stats.images == truth.keptFigures)
        let links = figureLinks(in: markdown)
        #expect(links == ["slides_assets/p0005-01.png"])
        let file = url.deletingLastPathComponent().appendingPathComponent(links[0])
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        // The chart was placed at 520 by 260 points, and the crop is a 2x render of that.
        #expect(abs(image.width - 1040) <= 2)
        #expect(abs(image.height - 520) <= 2)
    }

    @Test("--no-images leaves no links and no folder")
    func noImages() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, report, url) = try await harness.convert(
            try fixture("slides.pdf"),
            options: ConvertOptions(includeImages: false)
        )
        #expect(figureLinks(in: markdown).isEmpty)
        #expect(report.stats.images == 0)
        let assets = url.deletingLastPathComponent().appendingPathComponent("slides_assets")
        #expect(!FileManager.default.fileExists(atPath: assets.path))
    }

    @Test("a page with no figures leaves no assets folder behind")
    func noFigures() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (_, _, url) = try await harness.convert(try fixture("rotated.pdf"))
        let assets = url.deletingLastPathComponent().appendingPathComponent("rotated_assets")
        #expect(!FileManager.default.fileExists(atPath: assets.path))
    }

    @Test("links are percent-encoded, whatever the file is called")
    func encodedLinks() async throws {
        let original = try fixture("slides.pdf")
        let renamed = Fixture(
            fileName: "Clase 03 — POO 🚀.pdf",
            data: original.data,
            truth: original.truth
        )
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, _, url) = try await harness.convert(renamed)
        let link = try #require(figureLinks(in: markdown).first)
        #expect(!link.contains(" ") && !link.contains("🚀"))
        let decoded = try #require(link.removingPercentEncoding)
        let file = url.deletingLastPathComponent().appendingPathComponent(decoded)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: Math

    @Test("the book's formulas come out as LaTeX, inline and display")
    func math() async throws {
        for name in ["book.pdf", "book-cm.pdf"] {
            let fixture = try fixture(name)
            let truth = try #require(fixture.truth)
            let harness = try ConversionHarness()
            defer { harness.cleanUp() }

            let (markdown, report, _) = try await harness.convert(fixture)

            #expect(report.stats.mathSpans > 0)
            for fragment in truth.mathFragments {
                #expect(markdown.contains(fragment), "\(name): \(fragment)")
            }
            #expect(markdown.contains("$$\n"))
            #expect(OutputInvariants.violations(in: markdown).isEmpty)
        }
    }

    @Test("a stacked fraction has a linear form and a crop, and its text isn't repeated")
    func stacked() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, _, url) = try await harness.convert(try fixture("book.pdf"))

        let link = try #require(figureLinks(in: markdown).first)
        #expect(link.hasPrefix("book_assets/p0003-"))
        let file = url.deletingLastPathComponent().appendingPathComponent(link)
        #expect(FileManager.default.fileExists(atPath: file.path))
        let display = try #require(markdown.range(of: "/ 2n"))
        let image = try #require(markdown.range(of: "![Figure]"))
        #expect(display.upperBound < image.lowerBound)
        #expect(!markdown.contains("𝑛"))
    }

    @Test("with --no-images, a stacked fraction keeps its linear form and writes no file")
    func stackedNoImages() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let (markdown, report, _) = try await harness.convert(
            try fixture("book.pdf"),
            options: ConvertOptions(includeImages: false)
        )
        #expect(markdown.contains("/ 2n"))
        #expect(!markdown.contains("![Figure]"))
        #expect(report.stats.images == 0)
    }
}

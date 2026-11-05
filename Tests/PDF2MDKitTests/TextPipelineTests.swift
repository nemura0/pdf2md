import Foundation
import Testing

@testable import FixtureGen
@testable import PDF2MDKit

@Suite("Text pipeline")
struct TextPipelineTests {
    private func fixture(_ name: String) throws -> Fixture {
        try TestFixtures.named(name)
    }

    private func headings(in markdown: String) -> [GroundTruth.Heading] {
        markdown.split(separator: "\n").compactMap { line in
            guard let match = line.wholeMatch(of: /(#{2,6}) (.*)/) else { return nil }
            return GroundTruth.Heading(level: match.1.count, text: String(match.2))
        }
    }

    private func recall(_ wanted: [String], in text: String) -> (share: Double, missing: [String]) {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let missing = wanted.filter { !collapsed.contains($0) }
        let share = wanted.isEmpty ? 1 : 1 - Double(missing.count) / Double(wanted.count)
        return (share, missing)
    }

    @Test(
        "goldens match and hold the output invariants",
        arguments: ["book.pdf", "book-cm.pdf", "slides.pdf", "pdftex-style.pdf", "rotated.pdf"]
    )
    func goldens(name: String) async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let result = try await harness.convert(try fixture(name))
        #expect(OutputInvariants.violations(in: result.markdown) == [])

        let golden = (name as NSString).deletingPathExtension + ".md"
        if Golden.isUpdating { try Golden.write(result.markdown, to: golden) }
        #expect(result.markdown == (try Golden.read(golden)))
    }

    @Test("the book has its title, headings and words")
    func bookFidelity() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let book = try fixture("book.pdf")
        let truth = try #require(book.truth)
        let markdown = try await harness.convert(book).markdown

        #expect(markdown.contains("# Foundations of Computing\n"))
        let found = headings(in: markdown)
        for heading in truth.headings {
            #expect(found.contains(heading), "missing \(heading)")
        }
        let words = recall(truth.words, in: markdown)
        #expect(words.share > 0.99, "missing \(words.missing.prefix(20))")
    }

    @Test("running headers, footers and page numbers are gone")
    func margins() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        for name in ["book.pdf", "slides.pdf"] {
            let source = try fixture(name)
            let markdown = try await harness.convert(source).markdown
            let collapsed = markdown.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for line in try #require(source.truth).forbiddenLines {
                let wanted = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                #expect(!collapsed.contains(wanted), "\(name) kept \(line)")
            }
        }
    }

    @Test("code keeps its indentation and spacing")
    func code() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        for name in ["book.pdf", "slides.pdf"] {
            let source = try fixture(name)
            let markdown = try await harness.convert(source).markdown
            for line in try #require(source.truth).codeLines where !line.isEmpty {
                #expect(markdown.contains("\n" + line + "\n"), "\(name) lost `\(line)`")
            }
        }
    }

    @Test("two columns read left then right")
    func readingOrder() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let book = try fixture("book.pdf")
        let markdown = try await harness.convert(book).markdown
        let collapsed = markdown.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var position = collapsed.startIndex
        for phrase in try #require(book.truth).orderedPhrases {
            let range = try #require(
                collapsed.range(of: phrase, range: position..<collapsed.endIndex),
                "\(phrase) out of order"
            )
            position = range.upperBound
        }
    }

    @Test("a hyphen at the end of a line joins the word")
    func hyphenation() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let markdown = try await harness.convert(try fixture("book.pdf")).markdown
        #expect(markdown.contains("a comprehensive habit"))
    }

    @Test("slides: a useless metadata title is ignored, and titles become ##")
    func slides() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let deck = try fixture("slides.pdf")
        let markdown = try await harness.convert(deck).markdown
        #expect(markdown.contains("# \(SlidesFixture.deckTitle)\n"))
        #expect(!markdown.contains("PowerPoint Presentation"))
        let found = headings(in: markdown)
        for heading in try #require(deck.truth).headings {
            #expect(found.contains(heading), "missing \(heading)")
        }
    }

    @Test("options change the output as documented")
    func options() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let source = try fixture(EmojiNameFixture.fileName)
        let plain = try await harness.convert(
            source,
            options: ConvertOptions(includePageMarkers: false, includeFrontMatter: false)
        )
        #expect(!plain.markdown.contains("<!--"))
        #expect(plain.markdown.hasPrefix("# "))
        #expect(plain.url.lastPathComponent == "Clase 03 — Programación 🚀.md")

        let full = try await harness.convert(source)
        #expect(full.url.lastPathComponent == "Clase 03 — Programación 🚀 (1).md")
        #expect(full.markdown.hasPrefix("---\ntitle: \""))
        #expect(full.markdown.contains("source: \"Clase 03 — Programación 🚀.pdf\""))
        #expect(full.markdown.contains("pages: 2\n"))
        #expect(full.markdown.contains("converted: \"2026-01-01\""))
        #expect(full.markdown.contains("<!-- page 2 -->"))
    }

    @Test(
        "bad inputs fail with a short reason and leave nothing behind",
        arguments: [
            ("encrypted.pdf", "password-protected"),
            ("corrupt.pdf", "corrupt or unreadable PDF"),
            ("not-a-pdf.pdf", "not a PDF"),
            ("zero-pages.pdf", "corrupt or unreadable PDF"),
        ]
    )
    func failures(name: String, reason: String) async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        await #expect(throws: ConversionFailure(reason)) {
            _ = try await harness.convert(try fixture(name))
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: harness.directory.path)
        #expect(Set(left).subtracting(["home"]) == [name])
    }

    @Test("font facts come from the content stream, whatever PDFKit reports")
    func traceMatchRate() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        for name in ["book.pdf", "book-cm.pdf", "pdftex-style.pdf", "slides.pdf"] {
            let report = try await harness.convert(try fixture(name)).report
            #expect(report.stats.traceMatchRate > 0.97, "\(name): \(report.stats.traceMatchRate)")
        }
    }

    @Test("book-cm's renamed fonts give the same structure as the book")
    func bookCM() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let original = try await harness.convert(try fixture("book.pdf")).markdown
        let patched = try await harness.convert(try fixture("book-cm.pdf")).markdown
        #expect(headings(in: patched) == headings(in: original))
        #expect(patched.contains("public class Counter {"))
    }

    @Test("pdfTeX-style streams: kerned words, a CM mono line and a nested Form all come through")
    func pdfTeXStyle() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let source = try fixture("pdftex-style.pdf")
        let markdown = try await harness.convert(source).markdown
        #expect(markdown.contains("# A Paper in the pdfTeX Style"))
        #expect(markdown.contains("kerned"))
        #expect(markdown.contains("```\nint total = 0;\n```"))
        #expect(markdown.contains("Text inside a nested form"))
        #expect(markdown.contains("Form without resources"))
        #expect(markdown.contains("Office text"))
    }

    @Test("/Rotate pages read upright, in order")
    func rotated() async throws {
        let harness = try ConversionHarness()
        defer { harness.cleanUp() }
        let source = try fixture("rotated.pdf")
        let markdown = try await harness.convert(source).markdown
        let first = try #require(markdown.range(of: "Rotated first line of text"))
        let second = try #require(markdown.range(of: "Rotated second line of text"))
        #expect(first.lowerBound < second.lowerBound)
    }
}

import Foundation
import PDFKit
import Testing

@testable import FixtureGen

@Suite("FixtureGen")
struct FixtureGenTests {
    private func fixture(_ name: String) throws -> Fixture {
        let all = try TestFixtures.core()
        return try #require(all.first { $0.fileName == name })
    }

    @Test("generating twice gives identical bytes, except the salted encrypted file")
    func deterministic() throws {
        // The shared set goes first, so this is the only generation running in the process.
        let first = try TestFixtures.core()
        let second = try FixtureCatalog.core()
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) where a.fileName != "encrypted.pdf" {
            #expect(a.data == b.data, "\(a.fileName) changed between runs")
            #expect(a.truth == b.truth, "\(a.fileName) truth changed between runs")
        }
    }

    @Test("readable fixtures open with their expected page count")
    func openable() throws {
        let expectations = [
            "pdftex-style.pdf": 1, "rotated.pdf": 1, "slides.pdf": 7,
            "Clase 03 — Programación 🚀.pdf": 2,
        ]
        for (name, pages) in expectations {
            let document = try #require(PDFDocument(data: try fixture(name).data), "\(name)")
            #expect(document.pageCount == pages, "\(name)")
        }
    }

    @Test("the book has several pages of text and a scanned copy without any text")
    func bookAndScan() throws {
        let book = try #require(PDFDocument(data: try fixture("book.pdf").data))
        #expect(book.pageCount >= 6)
        #expect(
            book.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
                == "Foundations of Computing"
        )
        #expect(book.page(at: 1)?.string?.contains("Introduction") == true)

        let scan = try #require(PDFDocument(data: try fixture("scanned.pdf").data))
        #expect(scan.pageCount == book.pageCount)
        for index in 0..<scan.pageCount {
            #expect(scan.page(at: index)?.string?.isEmpty ?? true)
        }
    }

    @Test("failure fixtures fail in the right way")
    func failures() throws {
        let encrypted = try #require(PDFDocument(data: try fixture("encrypted.pdf").data))
        #expect(encrypted.isLocked)
        #expect(encrypted.unlock(withPassword: "open-sesame"))

        #expect(PDFDocument(data: try fixture("corrupt.pdf").data) == nil)
        #expect(PDFDocument(data: try fixture("not-a-pdf.pdf").data) == nil)

        let empty = PDFDocument(data: try fixture("zero-pages.pdf").data)
        #expect((empty?.pageCount ?? 0) == 0)
    }

    @Test("raw content streams decode: Differences Greek, Type0 text, nested and bare Forms")
    func pdfTeXStyleText() throws {
        let document = try #require(PDFDocument(data: try fixture("pdftex-style.pdf").data))
        let text = try #require(document.page(at: 0)?.string)
        #expect(text.contains("kerned"))
        #expect(text.contains("α"))
        #expect(text.contains("≤"))
        #expect(text.contains("β"))
        #expect(text.contains("Office text"))
        #expect(text.contains("Text inside a nested form"))
        #expect(text.contains("Form without resources"))
    }

    @Test("book-cm carries Computer Modern names in its font dictionaries")
    func patchedFonts() throws {
        let data = try fixture("book-cm.pdf").data
        for name in ["CMMI10xMathItalicXX", "CMTT10xRegula", "CMBX12xxxxBold", "CMR10xRoman"] {
            #expect(data.range(of: Data(name.utf8)) != nil, "\(name)")
        }
        #expect(data.range(of: Data("STIXTwoMath-Regular".utf8)) == nil)
        #expect(PDFDocument(data: data) != nil)
    }

    @Test("the rotated fixture really has a page rotation")
    func rotated() throws {
        let document = try #require(PDFDocument(data: try fixture("rotated.pdf").data))
        #expect(document.page(at: 0)?.rotation == 90)
    }
}

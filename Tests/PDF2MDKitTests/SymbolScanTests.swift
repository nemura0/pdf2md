import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import FixtureGen
@testable import PDF2MDKit

@Suite("Symbol codes in the content stream")
struct SymbolScanTests {
    /// A font with no `ToUnicode` and no `Encoding`, flagged as symbolic.
    private func pdf(showing text: String) -> Data {
        var writer = RawPDFWriter()
        let pages = writer.reserve()
        let font = """
            << /Type /Font /Subtype /Type1 /BaseFont /bbding /FirstChar 32 /LastChar 34 \
            /Widths [500 500 500] /FontDescriptor << /Type /FontDescriptor /FontName /bbding \
            /Flags 4 /FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 800 /Descent 0 \
            /CapHeight 700 /StemV 80 >> >>
            """
        let stream = writer.addStream("BT /Sym 10 Tf 50 700 Td (\(text)) Tj ET\n")
        let page = writer.add(
            """
            << /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 600 800] /Contents \(stream) \
            /Resources << /Font << /Sym \(font) >> >> >>
            """
        )
        writer.set(pages, "<< /Type /Pages /Kids [\(page)] /Count 1 >>")
        let catalog = writer.add("<< /Type /Catalog /Pages \(pages) 0 R >>")
        return writer.finish(root: catalog)
    }

    private func codes(in data: Data) throws -> [Int] {
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let reference = try #require(page.pageRef)
        let trace = ContentStreamScanner.scan(
            page: reference,
            geometry: DisplayGeometry(page: page)
        )
        return trace.runs.flatMap(\.symbolCodes)
    }

    @Test("a font with no text mapping has its codes recorded")
    func recorded() throws {
        #expect(try codes(in: pdf(showing: "\"\"")) == [34, 34])
    }

    /// One string can decompress to hundreds of megabytes, and each code takes 8 bytes.
    @Test("a run holds a limited number of codes")
    func limited() throws {
        let long = String(repeating: "\"", count: 5000)
        #expect(try codes(in: pdf(showing: long)).count == 256)
    }
}

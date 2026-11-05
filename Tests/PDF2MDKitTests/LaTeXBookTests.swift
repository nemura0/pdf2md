import Foundation
import Testing

@testable import FixtureGen
@testable import PDF2MDKit

/// Patterns found in a real LuaLaTeX book, which the CoreGraphics fixtures never produce.
@Suite("LaTeX book")
struct LaTeXBookTests {
    private func convert(
        options: ConvertOptions = ConvertOptions()
    ) async throws -> (markdown: String, report: ConversionReport, url: URL, harness: ConversionHarness) {
        let harness = try ConversionHarness()
        let result = try await harness.convert(
            try TestFixtures.named("latex-book.pdf"),
            options: options
        )
        return (result.markdown, result.report, result.url, harness)
    }

    @Test("a numbered listing is one fence, in order, with its numbers and indentation")
    func listing() async throws {
        let (markdown, _, _, harness) = try await convert()
        defer { harness.cleanUp() }
        let truth = try #require(try TestFixtures.named("latex-book.pdf").truth)
        let fence = "```\n" + truth.codeLines.joined(separator: "\n") + "\n```"
        #expect(markdown.contains(fence), "\(markdown)")
    }

    @Test("transparent images with identical pixels are different figures")
    func transparentImages() async throws {
        let (markdown, report, _, harness) = try await convert()
        defer { harness.cleanUp() }
        #expect(report.stats.images == 2)
        #expect(markdown.contains("p0002-01.png"))
        #expect(markdown.contains("p0003-01.png"))
    }
}

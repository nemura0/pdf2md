import Foundation
import Testing

@testable import FixtureGen
@testable import PDF2MDKit

/// Patterns found in a real LuaLaTeX book, which the CoreGraphics fixtures never produce.
@Suite("LaTeX book")
struct LaTeXBookTests {
    private func convert(
        options: ConvertOptions = ConvertOptions()
    ) async throws -> (
        markdown: String, report: ConversionReport, url: URL, harness: ConversionHarness
    ) {
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

    @Test("bullets drawn as small squares become a list")
    func vectorBullets() async throws {
        let (markdown, _, _, harness) = try await convert()
        defer { harness.cleanUp() }
        #expect(markdown.contains("- Manuales de desarrollo\n- Diagramas de diseno\n"))
    }

    @Test("a description list keeps each term with its whole paragraph")
    func descriptionList() async throws {
        let (markdown, _, _, harness) = try await convert()
        defer { harness.cleanUp() }
        let first =
            "**Diagnostico** En este punto simplemente diagnosticamos la situacion, para tener "
            + "una idea de cual es el problema que requiere un sistema de software.\n"
        let second =
            "**Factibilidad** Es necesario evaluar si el sistema de software es realmente la "
            + "solucion total. Se revisa si es factible de implementar.\n"
        #expect(markdown.contains(first), "\(markdown)")
        #expect(markdown.contains(second), "\(markdown)")
    }

    @Test("a URL wrapped at the end of a paragraph stays in it")
    func wrappedURL() async throws {
        let (markdown, _, _, harness) = try await convert()
        defer { harness.cleanUp() }
        #expect(markdown.contains("en `http://creative.org/licenses/`\n"), "\(markdown)")
    }
}

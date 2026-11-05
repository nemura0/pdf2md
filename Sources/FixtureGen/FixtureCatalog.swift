import Foundation

/// A generated document and what a correct conversion must contain.
struct Fixture: Sendable {
    let fileName: String
    let data: Data
    let truth: GroundTruth?
}

/// Every fixture, by name. All content is synthetic, and generation is deterministic.
enum FixtureCatalog {
    /// The fixtures fast enough to generate during `swift test`.
    static func core() throws -> [Fixture] {
        let book = try BookFixture.make()
        return [
            Fixture(fileName: "book.pdf", data: book.data, truth: book.truth),
            try FontPatchFixture.bookWithComputerModernNames(from: book),
            try SlidesFixture.make(),
            try ScannedFixture.make(from: book),
            try EmojiNameFixture.make(),
            RawFixtures.pdfTeXStyle(),
            LaTeXBookFixture.make(),
            OutlineBookFixture.make(hasOutline: true),
            OutlineBookFixture.make(hasOutline: false),
            DrawingBookFixture.make(),
            RawFixtures.rotated(),
            RawFixtures.zeroPages(),
            RawFixtures.corrupt(),
            RawFixtures.notAPDF(),
            try EncryptedFixture.make(),
        ]
    }

    static func writeCore(to directory: URL) throws {
        try write(try core(), to: directory)
    }

    static func writeLarge(to directory: URL) throws {
        try write([try LongDocumentFixture.make(name: "large-700.pdf", pages: 700)], to: directory)
    }

    /// The page-count series for the memory slope, plus heavy mixed documents.
    static func writeBench(to directory: URL) throws {
        for pages in [175, 350, 1400] {
            let fixture = try LongDocumentFixture.make(
                name: "bench-text-\(pages).pdf",
                pages: pages
            )
            try write([fixture], to: directory)
        }
        try write(
            [try BenchSlidesFixture.make(name: "bench-slides-400.pdf", slides: 400)],
            to: directory
        )
        try write(
            [try ScannedFixture.makeLong(name: "bench-scanned-300.pdf", pages: 300)],
            to: directory
        )
        try write(
            [try ScannedFixture.makeLong(name: "bench-scanned-700.pdf", pages: 700)],
            to: directory
        )
        try write(
            [try ScannedFixture.makeLong(name: "bench-scanned-1400.pdf", pages: 1400)],
            to: directory
        )
    }

    static func write(_ fixtures: [Fixture], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for fixture in fixtures {
            try fixture.data.write(to: directory.appendingPathComponent(fixture.fileName))
            guard let truth = fixture.truth else { continue }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let truthName = (fixture.fileName as NSString).deletingPathExtension + ".truth.json"
            try encoder.encode(truth).write(to: directory.appendingPathComponent(truthName))
        }
    }
}

/// Ground truth, recorded while drawing. Tests measure recall against it, because exact
/// goldens only prove that output is stable, not that it is right.
struct GroundTruth: Codable, Sendable, Equatable {
    struct Heading: Codable, Sendable, Equatable {
        let level: Int
        let text: String
    }

    var title = ""
    var pageCount = 0
    var headings: [Heading] = []
    /// Tables, each as rows of cells.
    var tables: [[[String]]] = []
    /// Words in body text, excluding margins and math.
    var words: [String] = []
    var codeLines: [String] = []
    /// Text that must not appear in the output: running headers, footers, page numbers.
    var forbiddenLines: [String] = []
    /// Phrases that must appear in this order, for reading-order checks.
    var orderedPhrases: [String] = []
    /// LaTeX fragments the math stage must produce.
    var mathFragments: [String] = []
    /// How many figures should be kept after filtering.
    var keptFigures = 0
}

enum FixtureError: Error, CustomStringConvertible {
    case contextCreationFailed(String)
    case renderFailed(String)

    var description: String {
        switch self {
        case .contextCreationFailed(let what): "could not create a context for \(what)"
        case .renderFailed(let what): "could not render \(what)"
        }
    }
}

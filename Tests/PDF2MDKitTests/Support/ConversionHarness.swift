import Foundation

@testable import FixtureGen
@testable import PDF2MDKit

/// The core fixtures, generated once per test process. Measured: generating them from every
/// parallel test blocked all the test threads in `CTFontCreateWithName` until a timeout, with
/// `fontd` otherwise answering other processes in milliseconds.
enum TestFixtures {
    private static let generated = Result { try FixtureCatalog.core() }

    static func core() throws -> [Fixture] {
        try generated.get()
    }

    static func named(_ name: String) throws -> Fixture {
        guard let fixture = try core().first(where: { $0.fileName == name }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return fixture
    }
}

/// Generates a fixture on disk and runs the real converter on it, in-process.
struct ConversionHarness {
    static let fixedDate = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01

    let directory: URL
    let paths: RuntimePaths

    init() throws {
        let manager = FileManager.default
        directory = manager.temporaryDirectory
            .appendingPathComponent("pdf2md-test-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        paths = RuntimePaths.under(directory.appendingPathComponent("home"))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    func convert(
        _ fixture: Fixture,
        options: ConvertOptions = ConvertOptions(),
        recognizer: any DocumentRecognizing = VisionDocumentRecognizer()
    ) async throws -> (markdown: String, report: ConversionReport, url: URL) {
        let pdf = directory.appendingPathComponent(fixture.fileName)
        try fixture.data.write(to: pdf)
        let converter = DocumentConverter(
            context: .init(
                paths: paths,
                jobs: 4,
                spoolDirectory: paths.caches.appendingPathComponent(UUID().uuidString),
                now: { Self.fixedDate },
                recognizer: recognizer
            )
        )
        let report = try await converter.convert(pdf: pdf, options: options)
        let url = URL(fileURLWithPath: report.output)
        return (try String(contentsOf: url, encoding: .utf8), report, url)
    }
}

/// Goldens live next to the tests. `UPDATE_GOLDENS=1 swift test` rewrites them, on purpose.
enum Golden {
    static func directory(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Golden", isDirectory: true)
    }

    static func read(_ name: String) throws -> String {
        try String(contentsOf: directory().appendingPathComponent(name), encoding: .utf8)
    }

    static func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: directory().appendingPathComponent(name))
    }

    static var isUpdating: Bool {
        ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1"
    }
}

/// Output invariants A11, asserted on every golden.
enum OutputInvariants {
    static func violations(in markdown: String) -> [String] {
        var problems: [String] = []
        var titleCount = 0
        var isInFence = false
        var previousBlank = false
        var isInFrontMatter = false
        for (index, line) in markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
        {
            if index == 0, line == "---" {
                isInFrontMatter = true
                continue
            }
            if isInFrontMatter {
                if line == "---" { isInFrontMatter = false }
                continue
            }
            if line.hasPrefix("```") { isInFence.toggle() }
            if line.last == " " || line.last == "\t" { problems.append("trailing space: \(line)") }
            let isBlank = line.isEmpty
            if isBlank, previousBlank, index > 0 {
                problems.append("double blank at line \(index)")
            }
            previousBlank = isBlank
            guard !isInFence else { continue }
            if line.hasPrefix("# ") { titleCount += 1 }
            if line.wholeMatch(of: /#{1,6}\s*/) != nil { problems.append("empty heading: \(line)") }
            let unescaped = line.replacingOccurrences(of: "\\<", with: "")
            if unescaped.contains(/<[a-zA-Z!\/]/), line.wholeMatch(of: /<!-- page \d+ -->/) == nil {
                problems.append("HTML: \(line)")
            }
        }
        if titleCount != 1 { problems.append("\(titleCount) titles") }
        if isInFence { problems.append("unclosed fence") }
        if !markdown.hasSuffix("\n") || markdown.hasSuffix("\n\n") {
            problems.append("must end in exactly one newline")
        }
        return problems
    }
}

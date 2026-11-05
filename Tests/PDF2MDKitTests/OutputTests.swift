import Foundation
import Testing

@testable import PDF2MDKit

@Suite("MarkdownRenderer")
struct MarkdownRendererTests {
    @Test("blocks render to Markdown")
    func blocks() {
        #expect(MarkdownRenderer.render(.heading(level: 3, text: "Name")) == "### Name")
        #expect(MarkdownRenderer.render(.paragraph("Text")) == "Text")
        #expect(MarkdownRenderer.render(.code(["a", "  b"])) == "```\na\n  b\n```")
        #expect(
            MarkdownRenderer.render(
                .list([
                    ListItem(depth: 0, marker: "-", text: "a"),
                    ListItem(depth: 1, marker: "-", text: "b"),
                    ListItem(depth: 0, marker: "10.", text: "c"),
                    ListItem(depth: 1, marker: "-", text: "d"),
                ])
            ) == "- a\n  - b\n10. c\n    - d"
        )
    }

    @Test("a fence grows when the code contains one")
    func longerFence() {
        #expect(MarkdownRenderer.render(.code(["```"])) == "````\n```\n````")
    }

    @Test("tables render as GFM with pipes escaped and rows padded")
    func tables() {
        let table = Block.table([["a|b", "c"], ["1"]])
        #expect(MarkdownRenderer.render(table) == "| a\\|b | c |\n| --- | --- |\n| 1 |  |")
    }

    @Test("figure links percent-encode the assets directory")
    func figures() {
        let block = Block.figure(path: "Clase 03 — Programación 🚀_assets/p0001-01.png")
        let rendered = MarkdownRenderer.render(block)
        #expect(rendered.hasPrefix("![Figure](Clase%2003%20"))
        #expect(rendered.hasSuffix("_assets/p0001-01.png)"))
        #expect(!rendered.contains("🚀"))
    }
}

@Suite("FrontMatter")
struct FrontMatterTests {
    @Test("values are double-quoted YAML, with quotes and backslashes escaped")
    func quoting() {
        let text = FrontMatter.render(
            title: #"A "quoted" \ title"#,
            source: "file.pdf",
            pages: 3,
            converted: "2026-01-01",
            tool: "pdf2md 1.0.0"
        )
        #expect(
            text == """
                ---
                title: "A \\"quoted\\" \\\\ title"
                source: "file.pdf"
                pages: 3
                converted: "2026-01-01"
                tool: "pdf2md 1.0.0"
                ---
                """
        )
    }
}

@Suite("MarkdownStream")
struct MarkdownStreamTests {
    private func written(_ build: (inout MarkdownStream) throws -> Void) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stream-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        var stream = try MarkdownStream(url: url)
        try build(&stream)
        try stream.close()
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("blocks are separated by exactly one blank line and the file ends in one newline")
    func spacing() throws {
        let text = try written { stream in
            try stream.write(block: "one\n\n")
            try stream.write(block: "   ")
            try stream.write(block: "\n\ntwo")
        }
        #expect(text == "one\n\ntwo\n")
    }

    @Test("trailing spaces and double blanks are removed, inside code too")
    func cleanup() throws {
        let text = try written { stream in
            try stream.write(block: "a  \nb\t\n\n\n\nc")
        }
        #expect(text == "a\nb\n\nc\n")
    }
}

@Suite("PageFlow")
struct PageFlowTests {
    private func flow(_ pages: [[Block]]) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        var stream = try MarkdownStream(url: url)
        var flow = PageFlow()
        for (index, page) in pages.enumerated() {
            try flow.write(page, pageMarker: "<!-- page \(index + 1) -->", to: &stream)
        }
        try flow.finish(to: &stream)
        try stream.close()
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("a paragraph split by a page break is joined, and the marker follows it")
    func joined() throws {
        let text = try flow([
            [.paragraph("It starts")], [.paragraph("and ends."), .heading(level: 2, text: "Next")],
        ])
        #expect(text == "<!-- page 1 -->\n\nIt starts and ends.\n\n<!-- page 2 -->\n\n## Next\n")
    }

    @Test("a paragraph over three pages stays one paragraph")
    func threePages() throws {
        let text = try flow([
            [.paragraph("One")], [.paragraph("two")],
            [.paragraph("three."), .heading(level: 2, text: "H")],
        ])
        #expect(
            text
                == "<!-- page 1 -->\n\nOne two three.\n\n<!-- page 2 -->\n\n<!-- page 3 -->\n\n## H\n"
        )
    }

    @Test("a list item split by a page break is joined, and the marker follows the list")
    func listItemJoined() throws {
        let items = [
            ListItem(depth: 0, marker: "-", text: "One."),
            ListItem(depth: 0, marker: "-", text: "It starts"),
        ]
        let text = try flow([[.list(items)], [.paragraph("and ends."), .paragraph("Next.")]])
        #expect(
            text == "<!-- page 1 -->\n\n- One.\n- It starts and ends.\n\n<!-- page 2 -->\n\nNext.\n"
        )
    }

    @Test("a finished list item isn't joined to the next page's text")
    func listItemFinished() throws {
        let items = [ListItem(depth: 0, marker: "-", text: "One.")]
        let text = try flow([[.list(items)], [.paragraph("next one")]])
        #expect(text == "<!-- page 1 -->\n\n- One.\n\n<!-- page 2 -->\n\nnext one\n")
    }

    @Test("a finished sentence or a capital starts a new paragraph on the new page")
    func notJoined() throws {
        let text = try flow([[.paragraph("Done.")], [.paragraph("next one")]])
        #expect(text == "<!-- page 1 -->\n\nDone.\n\n<!-- page 2 -->\n\nnext one\n")
    }
}

@Suite("Partial output")
struct PartialOutputTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a retracted path is no longer in the manifest")
    func retraction() throws {
        let directory = try makeDirectory()
        let manifest = JobManifest(url: directory.appendingPathComponent("m"))
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        try manifest.record([first, second])
        try manifest.forget([first])
        #expect(manifest.entries().map(\.lastPathComponent) == ["second"])
    }

    @Test("assets of an uncommitted placeholder go, and anything foreign inside keeps the folder")
    func assets() throws {
        let directory = try makeDirectory()
        let manager = FileManager.default
        let assets = directory.appendingPathComponent("doc_assets")
        try manager.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([1]).write(to: assets.appendingPathComponent("p0001-01.png"))
        try Data([1]).write(to: assets.appendingPathComponent("mine.txt"))
        let placeholder = directory.appendingPathComponent("doc.md")
        try Data().write(to: placeholder)

        PartialOutput.clean([placeholder, assets], caches: directory.appendingPathComponent("c"))
        #expect(!manager.fileExists(atPath: placeholder.path))
        #expect(!manager.fileExists(atPath: assets.appendingPathComponent("p0001-01.png").path))
        #expect(manager.fileExists(atPath: assets.appendingPathComponent("mine.txt").path))
    }

    @Test("a committed file keeps its assets")
    func committed() throws {
        let directory = try makeDirectory()
        let manager = FileManager.default
        let assets = directory.appendingPathComponent("doc_assets")
        try manager.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([1]).write(to: assets.appendingPathComponent("p0001-01.png"))
        let markdown = directory.appendingPathComponent("doc.md")
        try Data("# done".utf8).write(to: markdown)

        PartialOutput.clean([markdown, assets], caches: directory.appendingPathComponent("c"))
        #expect(manager.fileExists(atPath: markdown.path))
        #expect(manager.fileExists(atPath: assets.appendingPathComponent("p0001-01.png").path))
    }

    @Test("paths older than the job aren't touched, even if the manifest names them")
    func olderPaths() throws {
        let directory = try makeDirectory()
        let manager = FileManager.default
        let empty = directory.appendingPathComponent("yours.md")
        try Data().write(to: empty)
        let assets = directory.appendingPathComponent("yours_assets")
        try manager.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([1]).write(to: assets.appendingPathComponent("p0001-01.png"))

        PartialOutput.clean(
            [empty, assets],
            caches: directory.appendingPathComponent("c"),
            createdSince: Date().addingTimeInterval(60)
        )
        #expect(manager.fileExists(atPath: empty.path))
        #expect(manager.fileExists(atPath: assets.appendingPathComponent("p0001-01.png").path))
    }

    @Test("a path with a newline in its name survives the manifest as one path")
    func newlineInName() throws {
        let directory = try makeDirectory()
        let manifest = JobManifest(url: directory.appendingPathComponent("m"))
        let path = directory.appendingPathComponent("odd\n+name.md")
        try manifest.record([path])
        #expect(manifest.entries().map(\.path) == [path.path])
    }

    @Test("a directory outside the caches is never removed as a spool")
    func spoolScope() throws {
        let directory = try makeDirectory()
        let caches = directory.appendingPathComponent("caches")
        let spool = caches.appendingPathComponent("spool")
        let foreign = directory.appendingPathComponent("foreign")
        for url in [spool, foreign] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        PartialOutput.clean([spool, foreign], caches: caches)
        #expect(!FileManager.default.fileExists(atPath: spool.path))
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }

    @Test("a name lost to an existing assets folder doesn't leave it in the manifest")
    func abandonedReservation() throws {
        let directory = try makeDirectory()
        let manager = FileManager.default
        let existing = directory.appendingPathComponent("doc_assets")
        try manager.createDirectory(at: existing, withIntermediateDirectories: true)
        let manifest = JobManifest(url: directory.appendingPathComponent("m"))
        let reserved = try OutputWriter.reserve(
            pdf: directory.appendingPathComponent("doc.pdf"),
            options: ConvertOptions(),
            downloads: directory,
            beforeCreating: { try manifest.record($0) },
            didAbandon: { try manifest.forget($0) }
        )
        #expect(reserved.markdown.lastPathComponent == "doc (1).md")
        let names = Set(manifest.entries().map(\.lastPathComponent))
        #expect(!names.contains("doc_assets"))
        #expect(!names.contains("doc.md"))
        #expect(names.contains("doc (1).md"))
        #expect(names.contains("doc (1)_assets"))
    }
}

@Suite("OutputWriter")
struct OutputWriterTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func reserve(
        _ pdf: URL,
        options: ConvertOptions = ConvertOptions(),
        downloads: URL? = nil
    ) throws -> ReservedOutput {
        try OutputWriter.reserve(
            pdf: pdf,
            options: options,
            downloads: downloads ?? FileManager.default.temporaryDirectory,
            beforeCreating: { _ in }
        )
    }

    private func names(in directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    @Test("a reservation creates an empty placeholder and an assets directory")
    func reservation() throws {
        let directory = try makeDirectory()
        let reserved = try reserve(directory.appendingPathComponent("doc.pdf"))
        #expect(reserved.markdown.lastPathComponent == "doc.md")
        #expect(reserved.assets?.lastPathComponent == "doc_assets")
        #expect(try names(in: directory) == ["doc.md", "doc_assets"])
        let size = try FileManager.default.attributesOfItem(atPath: reserved.markdown.path)[.size]
        #expect(size as? Int == 0)
    }

    @Test("an existing output is never overwritten: the suffix goes up")
    func bump() throws {
        let directory = try makeDirectory()
        let pdf = directory.appendingPathComponent("doc.pdf")
        try Data("old".utf8).write(to: directory.appendingPathComponent("doc.md"))
        let first = try reserve(pdf)
        #expect(first.markdown.lastPathComponent == "doc (1).md")
        #expect(first.assets?.lastPathComponent == "doc (1)_assets")
        let second = try reserve(pdf)
        #expect(second.markdown.lastPathComponent == "doc (2).md")
        let old = try String(
            contentsOf: directory.appendingPathComponent("doc.md"),
            encoding: .utf8
        )
        #expect(old == "old")
    }

    @Test("an assets directory left by someone else bumps the pair together")
    func pairBump() throws {
        let directory = try makeDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("doc_assets"),
            withIntermediateDirectories: true
        )
        let reserved = try reserve(directory.appendingPathComponent("doc.pdf"))
        #expect(reserved.markdown.lastPathComponent == "doc (1).md")
        #expect(reserved.assets?.lastPathComponent == "doc (1)_assets")
        #expect(
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent("doc.md").path)
        )
    }

    @Test("concurrent reservations never share a name")
    func races() async throws {
        let directory = try makeDirectory()
        let pdf = directory.appendingPathComponent("doc.pdf")
        let results = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    try? OutputWriter.reserve(
                        pdf: pdf,
                        options: ConvertOptions(),
                        downloads: directory,
                        beforeCreating: { _ in }
                    ).markdown.lastPathComponent
                }
            }
            var names: [String] = []
            for await name in group {
                if let name { names.append(name) }
            }
            return names
        }
        #expect(results.count == 32)
        #expect(Set(results).count == 32)
    }

    @Test("--no-images reserves no assets directory")
    func noImages() throws {
        let directory = try makeDirectory()
        let reserved = try reserve(
            directory.appendingPathComponent("doc.pdf"),
            options: ConvertOptions(includeImages: false)
        )
        #expect(reserved.assets == nil)
        #expect(try names(in: directory) == ["doc.md"])
    }

    @Test("names keep spaces, accents and emoji")
    func names() throws {
        let directory = try makeDirectory()
        let reserved = try reserve(
            directory.appendingPathComponent("Clase 03 — Programación 🚀.pdf")
        )
        #expect(reserved.markdown.lastPathComponent == "Clase 03 — Programación 🚀.md")
    }

    @Test("an unwritable folder falls back to Downloads and says so")
    func fallback() throws {
        let locked = try makeDirectory()
        let downloads = try makeDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path
            )
        }
        let reserved = try reserve(locked.appendingPathComponent("doc.pdf"), downloads: downloads)
        #expect(reserved.didFallBack)
        #expect(reserved.markdown.deletingLastPathComponent().path == downloads.path)
    }

    @Test("an explicit --output-dir that can't be written is an error, with no silent move")
    func explicitOutputDirectory() throws {
        let locked = try makeDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path
            )
        }
        #expect(throws: ConversionFailure.self) {
            _ = try reserve(
                URL(fileURLWithPath: "/nowhere/doc.pdf"),
                options: ConvertOptions(outputDirectory: locked)
            )
        }
    }

    @Test("commit moves the images, swaps the temp in, and drops an empty assets directory")
    func commit() throws {
        let directory = try makeDirectory()
        let reserved = try reserve(directory.appendingPathComponent("doc.pdf"))
        try Data("# done\n".utf8).write(to: reserved.temporary)
        try OutputWriter.commit(reserved, images: [])
        #expect(try names(in: directory) == ["doc.md"])
        #expect(try String(contentsOf: reserved.markdown, encoding: .utf8) == "# done\n")

        let again = try reserve(directory.appendingPathComponent("doc.pdf"))
        let image = directory.appendingPathComponent("spooled.png")
        try Data([1, 2, 3]).write(to: image)
        try Data("second\n".utf8).write(to: again.temporary)
        try OutputWriter.commit(again, images: [(image, "p0001-01.png")])
        let assets = try #require(again.assets)
        #expect(try names(in: assets) == ["p0001-01.png"])
        #expect(!FileManager.default.fileExists(atPath: image.path))
    }

    @Test("a commit that fails part way leaves the overwritten output and its images whole")
    func overwriteFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = directory.appendingPathComponent("book_assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for name in ["p0001-01.png", "p0002-01.png"] {
            try Data("old".utf8).write(to: assets.appendingPathComponent(name))
        }
        let markdown = directory.appendingPathComponent("book.md")
        try Data("old".utf8).write(to: markdown)
        let temporary = directory.appendingPathComponent(".tmp")
        try Data("new".utf8).write(to: temporary)
        let source = directory.appendingPathComponent("new.png")
        try Data("new".utf8).write(to: source)
        let output = ReservedOutput(
            markdown: markdown,
            assets: assets,
            temporary: temporary,
            didFallBack: false,
            isOverwrite: true,
            ownsAssets: false
        )

        #expect(throws: (any Error).self) {
            try OutputWriter.commit(
                output,
                images: [
                    (source, "p0001-01.png"),
                    (directory.appendingPathComponent("missing.png"), "p0002-01.png"),
                ]
            )
        }

        #expect(try String(contentsOf: markdown, encoding: .utf8) == "old")
        let left = try FileManager.default.contentsOfDirectory(atPath: assets.path).sorted()
        #expect(left == ["p0001-01.png", "p0002-01.png"])
        let image = assets.appendingPathComponent("p0001-01.png")
        #expect(try String(contentsOf: image, encoding: .utf8) == "old")
    }

    @Test("a commit that succeeds replaces the images and leaves no staged files")
    func overwriteImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = directory.appendingPathComponent("book_assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let image = assets.appendingPathComponent("p0001-01.png")
        try Data("old".utf8).write(to: image)
        let temporary = directory.appendingPathComponent(".tmp")
        try Data("new".utf8).write(to: temporary)
        let source = directory.appendingPathComponent("new.png")
        try Data("new".utf8).write(to: source)
        let output = ReservedOutput(
            markdown: directory.appendingPathComponent("book.md"),
            assets: assets,
            temporary: temporary,
            didFallBack: false,
            isOverwrite: true,
            ownsAssets: false
        )

        try OutputWriter.commit(output, images: [(source, "p0001-01.png")])

        #expect(try String(contentsOf: image, encoding: .utf8) == "new")
        let left = try FileManager.default.contentsOfDirectory(atPath: assets.path)
        #expect(left == ["p0001-01.png"])
    }

    @Test("--overwrite leaves the original intact until the commit")
    func overwrite() throws {
        let directory = try makeDirectory()
        let target = directory.appendingPathComponent("doc.md")
        try Data("original".utf8).write(to: target)
        let reserved = try reserve(
            directory.appendingPathComponent("doc.pdf"),
            options: ConvertOptions(overwrite: true)
        )
        #expect(reserved.markdown == target)
        #expect(try String(contentsOf: target, encoding: .utf8) == "original")
        try Data("new".utf8).write(to: reserved.temporary)
        try OutputWriter.commit(reserved, images: [])
        #expect(try String(contentsOf: target, encoding: .utf8) == "new")
    }
}

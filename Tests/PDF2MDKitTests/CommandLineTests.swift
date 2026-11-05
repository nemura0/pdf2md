import Foundation
import Testing

@testable import FixtureGen
@testable import PDF2MDKit

/// Runs the built `pdf2md` binary and checks its exit codes and output.
@Suite("Command line")
struct CommandLineTests {
    @Test(
        "usage errors exit with 2",
        arguments: [
            ["--jobs", "0"],
            ["--no-such-flag"],
            ["--ocr", "sometimes", "a.pdf"],
            [String](),
            ["--cancel", "a.pdf"],
        ]
    )
    func usageErrors(arguments: [String]) throws {
        let result = try TestProcess.runCLI(arguments)
        #expect(result.status == 2, "stderr: \(result.stderr)")
        #expect(!result.stderr.isEmpty)
    }

    @Test("--help and --version exit with 0")
    func informational() throws {
        let help = try TestProcess.runCLI(["--help"])
        #expect(help.status == 0)
        #expect(help.stdout.contains("--output-dir"))

        let version = try TestProcess.runCLI(["--version"])
        #expect(version.status == 0)
        #expect(version.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1.0.0")
    }

    @Test("every documented flag is accepted")
    func allFlags() throws {
        let help = try TestProcess.runCLI(["--help"]).stdout
        for flag in [
            "--output-dir", "--overwrite", "--no-images", "--no-page-markers", "--no-front-matter",
            "--ocr", "--jobs", "--notify", "--detach", "--cancel", "--verbose",
        ] {
            #expect(help.contains(flag), "\(flag)")
        }
    }
}

/// Runs whole conversions through the supervisor and its child processes.
@Suite("Supervisor")
struct SupervisorTests {
    private struct Workspace {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var environment: [String: String] {
            ["PDF2MD_HOME": home.path, "PDF2MD_DOWNLOADS": home.appendingPathComponent("dl").path]
        }

        init(fixtures: [Fixture]) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("pdf2md-cli-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for fixture in fixtures {
                try fixture.data.write(to: root.appendingPathComponent(fixture.fileName))
            }
        }

        func path(_ name: String) -> String { root.appendingPathComponent(name).path }

        func names(in directory: URL? = nil) throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: (directory ?? root).path))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private func fixtures(_ names: [String]) throws -> [Fixture] {
        try names.map(TestFixtures.named)
    }

    @Test("one bad file doesn't stop the others, and the exit code says some failed")
    func mixedRun() throws {
        let names = ["book.pdf", "corrupt.pdf", "encrypted.pdf", "not-a-pdf.pdf", "slides.pdf"]
        let workspace = try Workspace(fixtures: try fixtures(names))
        defer { workspace.remove() }
        let result = try TestProcess.runCLI(
            names.map(workspace.path) + ["--jobs", "2"],
            environment: workspace.environment
        )
        #expect(result.status == 1)
        #expect(result.stderr.contains("Converted 2 of 5"))
        #expect(result.stderr.contains("encrypted.pdf: password-protected"))
        #expect(try workspace.names() == Set(names + ["book.md", "slides.md", "slides_assets", "home"]))

        let jobs = workspace.home.appendingPathComponent("jobs")
        #expect(try workspace.names(in: jobs).isEmpty)
        #expect(try workspace.names(in: workspace.home.appendingPathComponent("caches")).isEmpty)

        let log = try String(
            contentsOf: workspace.home.appendingPathComponent("logs/pdf2md.log"),
            encoding: .utf8
        )
        #expect(log.split(separator: "\n").count == 5)
        #expect(log.contains(#"failed file="corrupt.pdf""#))
        #expect(log.contains(#"ok file="book.pdf" pages=6"#))
    }

    @Test("a successful run exits with 0, and flags reach the converter")
    func successfulRun() throws {
        let workspace = try Workspace(fixtures: try fixtures(["book.pdf"]))
        defer { workspace.remove() }
        let output = workspace.root.appendingPathComponent("made/here")
        let result = try TestProcess.runCLI(
            [
                workspace.path("book.pdf"), "--output-dir", output.path, "--no-page-markers",
                "--no-front-matter", "--verbose",
            ],
            environment: workspace.environment
        )
        #expect(result.status == 0, "stderr: \(result.stderr)")
        #expect(result.stderr.contains("font match"))
        let markdown = try String(
            contentsOf: output.appendingPathComponent("book.md"),
            encoding: .utf8
        )
        #expect(markdown.hasPrefix("# Foundations of Computing"))
        #expect(!markdown.contains("<!--"))
    }

    @Test("a stale job from a dead process is swept, and finished output survives")
    func staleSweep() throws {
        let workspace = try Workspace(fixtures: try fixtures(["book.pdf"]))
        defer { workspace.remove() }
        let manager = FileManager.default
        let job = workspace.home.appendingPathComponent("jobs/dead")
        try manager.createDirectory(at: job, withIntermediateDirectories: true)
        try Data().write(to: job.appendingPathComponent("job.lock"))

        let placeholder = workspace.root.appendingPathComponent("partial.md")
        try Data().write(to: placeholder)
        let temporary = workspace.root.appendingPathComponent(".partial.md.x.pdf2md-tmp")
        try Data("half".utf8).write(to: temporary)
        let finished = workspace.root.appendingPathComponent("finished.md")
        try Data("done".utf8).write(to: finished)
        let manifest = JobManifest(url: job.appendingPathComponent("file-0.manifest"))
        try manifest.record([placeholder, temporary, finished])

        let result = try TestProcess.runCLI(
            [workspace.path("book.pdf")],
            environment: workspace.environment
        )
        #expect(result.status == 0)
        #expect(!manager.fileExists(atPath: placeholder.path))
        #expect(!manager.fileExists(atPath: temporary.path))
        #expect(manager.fileExists(atPath: finished.path))
        #expect(!manager.fileExists(atPath: job.path))
    }
}

/// Spawns the built CLI.
enum TestProcess {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// The executable sits next to the test bundle, or above its resources, depending on the
    /// build system SwiftPM uses. Walk up instead of assuming a layout.
    static var cliURL: URL {
        get throws {
            var directory = Bundle.module.bundleURL
            while directory.path != "/" {
                directory.deleteLastPathComponent()
                let candidate = directory.appendingPathComponent("pdf2md")
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(
                    atPath: candidate.path,
                    isDirectory: &isDirectory
                ),
                    !isDirectory.boolValue
                {
                    return candidate
                }
            }
            throw CocoaError(.fileNoSuchFile)
        }
    }

    static func runCLI(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> Result {
        let process = Process()
        process.executableURL = try cliURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self)
        )
    }
}

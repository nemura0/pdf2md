import Foundation
import Testing

@testable import FixtureGen
@testable import PDF2MDKit

/// Runs the built `pdf2md` binary and checks its exit codes and output.
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
        #expect(
            try workspace.names()
                == Set(names + ["book.md", "book_assets", "slides.md", "slides_assets", "home"])
        )

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

/// A small deterministic generator, so a failing mutation can be replayed from its seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@Suite("Fuzz smoke")
struct FuzzSmokeTests {
    private static let filesPerFixture = 12
    private static let flippedBytes = 40

    private func mutated(_ data: Data, seed: UInt64) -> Data {
        var generator = SplitMix64(state: seed)
        var bytes = [UInt8](data)
        for _ in 0..<Self.flippedBytes {
            bytes[Int.random(in: 0..<bytes.count, using: &generator)] = UInt8.random(
                in: 0...255,
                using: &generator
            )
        }
        return Data(bytes)
    }

    @Test("byte-mutated PDFs end in a result or a clean failure, and never disturb the good file")
    func mutatedFiles() throws {
        let workspace = try Workspace(fixtures: [])
        defer { workspace.remove() }
        var names: [String] = []
        for (index, name) in ["book.pdf", "pdftex-style.pdf", "slides.pdf"].enumerated() {
            let source = try TestFixtures.named(name)
            for copy in 0..<Self.filesPerFixture {
                let fileName = "fuzz-\(index)-\(copy).pdf"
                let seed = UInt64(index * 1000 + copy)
                try mutated(source.data, seed: seed).write(
                    to: workspace.root.appendingPathComponent(fileName)
                )
                names.append(fileName)
            }
        }
        let good = try TestFixtures.named("book.pdf")
        try good.data.write(to: workspace.root.appendingPathComponent("good.pdf"))

        var environment = workspace.environment
        environment["PDF2MD_WATCHDOG_SECONDS"] = "60"
        let result = try TestProcess.runCLI(
            (names + ["good.pdf"]).map(workspace.path),
            environment: environment
        )

        #expect(result.status == 0 || result.status == 1)
        #expect(try workspace.names().contains("good.md"))
        let converted = try workspace.names().filter { $0.hasSuffix(".md") }.count
        let failed = result.stderr.split(separator: "\n").filter { $0.hasPrefix("failed: ") }
        #expect(converted + failed.count == names.count + 1)
        let leftovers = try workspace.names().filter { $0.hasSuffix(PartialOutput.temporarySuffix) }
        #expect(leftovers.isEmpty)
        let jobs = workspace.home.appendingPathComponent("jobs")
        #expect(try workspace.names(in: jobs).isEmpty)
    }
}

@Suite("Notification text")
struct NotificationTextTests {
    private func outcome(_ name: String, error: String? = nil) -> FileOutcome {
        FileOutcome(input: URL(fileURLWithPath: "/tmp/\(name)"), error: error)
    }

    private func summary(_ outcomes: [FileOutcome]) -> RunSummary {
        RunSummary(outcomes: outcomes, duration: 134)
    }

    @Test("the start names the count, in the singular too")
    func started() {
        #expect(NotificationText.started(fileCount: 3) == "Converting 3 PDFs…")
        #expect(NotificationText.started(fileCount: 1) == "Converting 1 PDF…")
    }

    @Test("the end has the headline, and failures with short reasons")
    func finished() {
        let text = NotificationText.finished(
            summary([outcome("a.pdf"), outcome("b.pdf", error: "password-protected")])
        )
        #expect(text == "Converted 1 of 2 in 2m 14s\nb.pdf: password-protected")
    }

    @Test("failures that don't fit point to the log instead")
    func tooMany() {
        let failures = (0..<40).map {
            outcome("file-\($0).pdf", error: "corrupt or unreadable PDF")
        }
        let text = NotificationText.finished(summary(failures))
        #expect(text.count <= 200)
        #expect(text.hasPrefix("Converted 0 of 40"))
        #expect(text.contains("file-0.pdf"))
        #expect(text.hasSuffix("Details: ~/Library/Logs/pdf2md/pdf2md.log"))
    }

    @Test("a fallback to Downloads is mentioned, and cancelled files aren't failures to list")
    func others() {
        var moved = outcome("a.pdf")
        moved.didFallBack = true
        let text = NotificationText.finished(
            summary([moved, outcome("b.pdf", error: "cancelled")])
        )
        #expect(text.hasPrefix("Cancelled. Converted 1 of 2"))
        #expect(text.contains("saved to Downloads"))
        #expect(!text.contains("b.pdf"))
    }
}

@Suite("Detach handshake and pid checks")
struct DetachHandshakeTests {
    @Test("a process that dies before registering is reported, not taken for success")
    func diedEarly() {
        #expect(throws: ConversionFailure.self) {
            try ProcessSpawner.spawnDetached(
                executable: "/usr/bin/true",
                arguments: [],
                readyDescriptor: 3
            )
        }
    }

    @Test("a process that signals it's ready returns at once, even if it keeps running")
    func signalled() throws {
        let started = Date()
        try ProcessSpawner.spawnDetached(
            executable: "/bin/sh",
            arguments: ["-c", "printf x >&3; exec 3>&-; sleep 3"],
            readyDescriptor: 3
        )
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test("a recorded pid only counts if it's still this tool")
    func pidCheck() {
        #expect(!JobHandle.isTool(getpid()))
        #expect(!JobHandle.isTool(-1))
    }
}

@Suite("Detach and cancel", .serialized)
struct DetachAndCancelTests {
    /// A stub that records each notification, standing in for `osascript`.
    private func installStub(in workspace: Workspace) throws -> (path: String, log: URL) {
        let log = workspace.root.appendingPathComponent("notifications.txt")
        let script = workspace.root.appendingPathComponent("osascript-stub")
        let text = """
            #!/bin/sh
            for last; do :; done
            printf '%s\\n--\\n' "$last" >> "\(log.path)"
            """
        try text.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script.path, log)
    }

    private func waitUntil(seconds: Double = 60, _ condition: () throws -> Bool) rethrows -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func longFixture() throws -> Fixture {
        try LongDocumentFixture.make(name: "long.pdf", pages: 500)
    }

    @Test("--detach returns at once, the job goes on, and notifications come at both ends")
    func detach() throws {
        let workspace = try Workspace(fixtures: [try longFixture()])
        defer { workspace.remove() }
        let stub = try installStub(in: workspace)
        var environment = workspace.environment
        environment["PDF2MD_OSASCRIPT"] = stub.path

        let started = Date()
        let result = try TestProcess.runCLI(
            [workspace.path("long.pdf"), "--detach", "--notify"],
            environment: environment
        )
        #expect(result.status == 0)
        #expect(Date().timeIntervalSince(started) < 3)
        #expect(!(try workspace.names().contains("long.md")))

        let isDone = waitUntil {
            ((try? String(contentsOf: stub.log, encoding: .utf8)) ?? "").contains("Converted")
        }
        #expect(isDone)
        #expect(try workspace.names().contains("long.md"))
        let text = try String(contentsOf: stub.log, encoding: .utf8)
        #expect(text.hasPrefix("Converting 1 PDF…\n--\n"))
        #expect(text.contains("Converted 1 of 1 in"))
    }

    @Test("--cancel stops a detached job and leaves no partial output, and a file name stays argv")
    func cancel() throws {
        let original = try longFixture()
        let name = #"long "quoted" & more.pdf"#
        let fixture = Fixture(fileName: name, data: original.data, truth: nil)
        let workspace = try Workspace(fixtures: [fixture])
        defer { workspace.remove() }

        let detached = try TestProcess.runCLI(
            [workspace.path(name), "--detach"],
            environment: workspace.environment
        )
        #expect(detached.status == 0)

        let cancelled = try TestProcess.runCLI(["--cancel"], environment: workspace.environment)
        #expect(cancelled.status == 0)
        #expect(cancelled.stdout.contains("Cancelled 1"))

        #expect(try workspace.names() == [name, "home"])
        let jobs = workspace.home.appendingPathComponent("jobs")
        #expect(try workspace.names(in: jobs).isEmpty)

        let again = try TestProcess.runCLI(["--cancel"], environment: workspace.environment)
        #expect(again.stdout.contains("Nothing to cancel"))
    }

    @Test("--cancel never deletes an output that an earlier run finished")
    func cancelKeepsFinished() throws {
        let workspace = try Workspace(fixtures: [try TestFixtures.named("book.pdf")])
        defer { workspace.remove() }
        _ = try TestProcess.runCLI([workspace.path("book.pdf")], environment: workspace.environment)
        let cancelled = try TestProcess.runCLI(["--cancel"], environment: workspace.environment)
        #expect(cancelled.status == 0)
        #expect(try workspace.names().contains("book.md"))
    }
}

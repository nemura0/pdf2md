import Foundation
import Testing

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

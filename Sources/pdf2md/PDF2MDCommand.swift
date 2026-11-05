import ArgumentParser
import Foundation
import PDF2MDKit

@main
struct PDF2MDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdf2md",
        abstract: "Convert PDFs to compact Markdown, offline.",
        discussion: """
            Writes <name>.md next to each PDF. Exit codes: 0 all converted, 1 some failed, \
            2 usage error. Log: ~/Library/Logs/pdf2md/pdf2md.log
            """,
        version: PDF2MDVersion.current
    )

    @Option(name: .long, help: "Write output here instead of next to each PDF.")
    var outputDir: String?

    @Flag(name: .long, help: "Replace an existing output instead of adding (1), (2)…")
    var overwrite = false

    @Flag(name: .long, help: "Don't extract figures.")
    var noImages = false

    @Flag(name: .long, help: "Omit <!-- page N --> markers.")
    var noPageMarkers = false

    @Flag(name: .long, help: "Omit the YAML front matter.")
    var noFrontMatter = false

    @Option(name: .long, help: "When to OCR pages: auto, always or never.")
    var ocr: OCRMode = .auto

    @Option(name: .long, help: "Maximum concurrent page tasks (default: performance cores).")
    var jobs: Int?

    @Flag(name: .long, help: "Send a notification at the start and at the end.")
    var notify = false

    @Flag(name: .long, help: "Run in a new session and return immediately.")
    var detach = false

    @Flag(name: .long, help: "Stop running jobs and remove their partial output.")
    var cancel = false

    @Flag(name: .long, help: "Print per-file statistics.")
    var verbose = false

    /// Set by `--detach` on the process it starts. Closing this tells the parent to return.
    @Option(name: .long, help: .hidden)
    var readyFd: Int32?

    @Argument(help: "PDF files to convert.", completion: .file(extensions: ["pdf"]))
    var files: [String] = []

    func validate() throws {
        if let jobs, jobs < 1 {
            throw ValidationError("--jobs must be at least 1.")
        }
        if cancel, !files.isEmpty {
            throw ValidationError("--cancel doesn't take files.")
        }
        if !cancel, files.isEmpty {
            throw ValidationError("Missing PDF files. Use --help for usage.")
        }
    }

    func run() async throws {
        if cancel {
            let count = JobHandle.cancelRunning(paths: .current())
            print(count == 0 ? "Nothing to cancel." : "Cancelled \(count) running job(s).")
            return
        }
        if detach {
            try detachFromSession()
            return
        }
        let notifier: (any Notifying)? = notify ? OsascriptNotifier() : nil
        let options = ConvertOptions(
            outputDirectory: outputDir.map { URL(fileURLWithPath: $0, isDirectory: true) },
            overwrite: overwrite,
            includeImages: !noImages,
            includePageMarkers: !noPageMarkers,
            includeFrontMatter: !noFrontMatter,
            ocrMode: ocr
        )
        let summary = await Supervisor.run(
            RunRequest(
                files: files.map { URL(fileURLWithPath: $0) },
                options: options,
                jobs: jobs,
                isVerbose: verbose,
                showsProgress: true,
                onRegistered: { [readyFd, files] in
                    if let readyFd { close(readyFd) }
                    notifier?.send(NotificationText.started(fileCount: files.count))
                }
            )
        )
        notifier?.send(NotificationText.finished(summary))
        throw summary.isCompleteSuccess ? ExitCode.success : ExitCode.failure
    }

    /// Starts the same command in a new session and returns. The caller's arguments go as they
    /// are, minus the flag itself, and relative paths still work since the directory is inherited.
    private func detachFromSession() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if let flag = arguments.firstIndex(of: "--detach") { arguments.remove(at: flag) }
        let descriptor: Int32 = 3
        try ProcessSpawner.spawnDetached(
            arguments: ["--ready-fd", String(descriptor)] + arguments,
            readyDescriptor: descriptor
        )
    }

    /// Replaces ArgumentParser's default entry point, because usage errors must exit with 2,
    /// not the default 64 (EX_USAGE).
    static func main() async {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == ChildRequest.argument {
            await ConversionChild.run(json: arguments[2])
        }
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            finish(with: error)
        }
    }

    private static func finish(with error: any Error) -> Never {
        let code = exitCode(for: error)
        let message = fullMessage(for: error)
        if !message.isEmpty {
            let stream = code == .success ? FileHandle.standardOutput : FileHandle.standardError
            stream.write(Data((message + "\n").utf8))
        }
        Foundation.exit(code == .validationFailure ? usageErrorExitCode : code.rawValue)
    }

    private static let usageErrorExitCode: Int32 = 2
}

extension OCRMode: ExpressibleByArgument {}

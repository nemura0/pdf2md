import Foundation

/// What the supervisor tells a child to do, passed as one JSON argument.
public struct ChildRequest: Sendable, Codable {
    public static let argument = "__convert-child"

    public var pdf: String
    public var options: ConvertOptions
    public var jobs: Int
    public var manifest: String
    public var jobLock: String
    public var spool: String
}

/// One JSON line on the child's stdout.
public enum ChildEvent: Sendable, Codable {
    case opening
    case started(pages: Int)
    case page(done: Int, total: Int)
    case finished(ConversionReport)
    case failed(reason: String)
}

/// The entry point of the per-file child process (ADR-0007).
public enum ConversionChild {
    private static let abandonedExitCode: Int32 = 75

    public static func run(json: String) async -> Never {
        guard let request = try? JSONDecoder().decode(ChildRequest.self, from: Data(json.utf8))
        else {
            emit(.failed(reason: "internal error: bad child request"))
            _exit(1)
        }
        exitWhenSupervisorIsGone()
        // Held until exit, so the job's lock stays busy while this process can still write.
        let jobLock: FileSlot
        do {
            jobLock = try FileSlot(url: URL(fileURLWithPath: request.jobLock))
        } catch {
            // Without the lock, a sweep could clean up under a live conversion.
            emit(.failed(reason: "couldn't join the job"))
            _exit(1)
        }
        jobLock.lockShared()

        let manifest = JobManifest(url: URL(fileURLWithPath: request.manifest))
        let converter = DocumentConverter(
            context: .init(
                paths: .current(),
                jobs: request.jobs,
                spoolDirectory: URL(fileURLWithPath: request.spool, isDirectory: true),
                onOpening: { emit(.opening) },
                onStarted: { emit(.started(pages: $0)) },
                onPage: { emit(.page(done: $0, total: $1)) },
                recordPaths: { try manifest.record($0) },
                forgetPaths: { try manifest.forget($0) }
            )
        )
        do {
            let report = try await converter.convert(
                pdf: URL(fileURLWithPath: request.pdf),
                options: request.options
            )
            emit(.finished(report))
            finish(status: 0, holding: jobLock)
        } catch let failure as ConversionFailure {
            emit(.failed(reason: failure.reason))
        } catch {
            emit(.failed(reason: error.localizedDescription))
        }
        finish(status: 1, holding: jobLock)
    }

    /// `_exit` rather than `exit`: atexit handlers with framework threads alive are a place to
    /// hang, and everything that matters is already on disk. `withExtendedLifetime` keeps the
    /// job lock until the process is gone.
    private static func finish(status: Int32, holding lock: FileSlot) -> Never {
        withExtendedLifetime(lock) { _exit(status) }
    }

    /// The control pipe closes when the supervisor dies, however it dies, so no writer outlives it.
    private static func exitWhenSupervisorIsGone() {
        Thread.detachNewThread {
            var byte: UInt8 = 0
            while true {
                let count = read(STDIN_FILENO, &byte, 1)
                if count == 0 || (count < 0 && errno != EINTR) { _exit(abandonedExitCode) }
            }
        }
    }

    private static func emit(_ event: ChildEvent) {
        guard var data = try? JSONEncoder().encode(event) else { return }
        data.append(0x0A)
        // One write per line, below PIPE_BUF for everything but a huge report, from any thread.
        _ = data.withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress, $0.count) }
    }
}

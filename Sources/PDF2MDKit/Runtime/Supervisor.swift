import Darwin
import Foundation
import Synchronization

/// What happened to one input file.
public struct FileOutcome: Sendable {
    public var input: URL
    public var output: String?
    public var error: String?
    public var didFallBack = false
    public var stats = ConversionStats()
    public var duration = 0.0
}

/// The result of a whole run.
public struct RunSummary: Sendable {
    public var outcomes: [FileOutcome]
    public var duration: Double

    public var succeeded: Int { outcomes.filter { $0.error == nil }.count }
    public var isCompleteSuccess: Bool { succeeded == outcomes.count }

    public var headline: String {
        "Converted \(succeeded) of \(outcomes.count) in \(Self.formatted(duration))"
    }

    static func formatted(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \(total / 60 % 60)m"
    }
}

/// How a run should behave, independent of how it was launched.
public struct RunRequest: Sendable {
    public var files: [URL]
    public var options: ConvertOptions
    public var jobs: Int
    public var isVerbose: Bool
    public var showsProgress: Bool
    /// Runs once the job is registered and `--cancel` can see it.
    public var onRegistered: @Sendable () -> Void

    public init(
        files: [URL],
        options: ConvertOptions,
        jobs: Int?,
        isVerbose: Bool,
        showsProgress: Bool,
        onRegistered: @escaping @Sendable () -> Void = {}
    ) {
        self.files = files
        self.options = options
        self.jobs = jobs ?? Supervisor.defaultPageLimit
        self.isVerbose = isVerbose
        self.showsProgress = showsProgress
        self.onRegistered = onRegistered
    }
}

/// Converts files, one supervised child process per file, so a crash or hang in the PDF frameworks
/// costs that file only (A8). Limits are global across runs through slot files (A9).
public enum Supervisor {
    /// More files at once mostly adds memory, since the page limit is what bounds the CPU.
    private static let maximumFiles = 3
    private static let slotPollNanoseconds: UInt64 = 100_000_000

    public static var defaultPageLimit: Int {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0
        else { return max(1, ProcessInfo.processInfo.activeProcessorCount / 2) }
        return Int(cores)
    }

    public static func run(_ request: RunRequest) async -> RunSummary {
        let paths = RuntimePaths.current()
        let started = Date()
        JobHandle.sweepStale(paths: paths)
        let progress = ProgressReporter(isEnabled: request.showsProgress)
        let log = ConversionLog(url: paths.log)
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Converting PDFs to Markdown"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        let job: JobHandle
        do {
            job = try JobHandle(paths: paths)
        } catch {
            let outcomes = request.files.map {
                FileOutcome(input: $0, error: "couldn't start: \(error.localizedDescription)")
            }
            request.onRegistered()
            return RunSummary(outcomes: outcomes, duration: 0)
        }
        defer { job.finish() }

        if let directory = request.options.outputDirectory {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let run = RunContext(
            request: request,
            paths: paths,
            manifests: request.files.indices.map { job.manifest(forFile: $0) },
            pidFiles: request.files.indices.map { job.childPIDFile(forFile: $0) },
            jobLock: job.lockURL,
            jobStart: started,
            log: log,
            progress: progress
        )
        let signals = run.handleSignals()
        defer { signals.forEach { $0.cancel() } }
        // Only now, so a `--cancel` right after this reaches a process that handles it.
        request.onRegistered()

        let outcomes = await convertAll(run)
        let summary = RunSummary(outcomes: outcomes, duration: Date().timeIntervalSince(started))
        progress.line(summary.headline)
        return summary
    }

    private static func convertAll(_ run: RunContext) async -> [FileOutcome] {
        let queue = FileQueue(count: run.request.files.count)
        let runners = min(maximumFiles, run.request.jobs, run.request.files.count)
        var results = [FileOutcome?](repeating: nil, count: run.request.files.count)
        await withDiscardingTaskGroup { group in
            for _ in 0..<max(runners, 1) {
                group.addTask {
                    while let index = await queue.take() {
                        await queue.store(await convert(index: index, run: run), at: index)
                    }
                }
            }
        }
        for (index, outcome) in await queue.outcomes() { results[index] = outcome }
        return zip(run.request.files, results).map { file, outcome in
            outcome ?? FileOutcome(input: file, error: "not converted")
        }
    }

    private static func convert(index: Int, run: RunContext) async -> FileOutcome {
        let input = run.request.files[index]
        let started = Date()
        var outcome = FileOutcome(input: input)
        let slot: FileSlot?
        do {
            slot = try await acquireFileSlot(run: run)
        } catch {
            outcome.error = (error as? ConversionFailure)?.reason ?? error.localizedDescription
            run.report(outcome)
            return outcome
        }
        defer { slot?.unlock() }
        if run.isCancelled {
            outcome.error = "cancelled"
            run.report(outcome)
            return outcome
        }
        let manifest = run.manifests[index]
        let ending: ChildMonitor.Ending
        do {
            ending = try await runChild(index: index, run: run)
        } catch {
            ending = .failed(
                (error as? ConversionFailure)?.reason ?? error.localizedDescription
            )
        }
        apply(ending, to: &outcome, isCancelled: run.isCancelled)
        outcome.duration = Date().timeIntervalSince(started)
        if outcome.error != nil {
            PartialOutput.clean(
                manifest.entries(),
                caches: run.paths.caches,
                createdSince: run.jobStart
            )
        }
        manifest.remove()
        run.report(outcome)
        return outcome
    }

    private static func apply(
        _ ending: ChildMonitor.Ending,
        to outcome: inout FileOutcome,
        isCancelled: Bool
    ) {
        switch ending {
        case .finished(let report):
            outcome.output = report.output
            outcome.stats = report.stats
            outcome.didFallBack = report.didFallBack
        case .failed(let reason):
            outcome.error = reason
        case .hung:
            outcome.error = "stopped responding"
        case .crashed(let signal):
            if isCancelled {
                outcome.error = "cancelled"
            } else {
                outcome.error = signal.map { "crashed (signal \($0))" } ?? "the worker stopped"
            }
        }
    }

    private static func runChild(index: Int, run: RunContext) async throws -> ChildMonitor.Ending {
        let input = run.request.files[index]
        let spool = run.paths.caches.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: run.paths.caches,
            withIntermediateDirectories: true
        )
        let childRequest = ChildRequest(
            pdf: input.path,
            options: run.request.options,
            jobs: run.request.jobs,
            manifest: run.manifests[index].url.path,
            jobLock: run.jobLock.path,
            spool: spool.path
        )
        let json = String(decoding: try JSONEncoder().encode(childRequest), as: UTF8.self)
        let child = try ProcessSpawner.spawnChild(arguments: [ChildRequest.argument, json])
        run.register(child: child.pid, index: index)

        let name = input.lastPathComponent
        let progress = run.progress
        let monitor = ChildMonitor(
            child: child,
            beforeReap: { run.unregister(child: child.pid) }
        ) { event in
            if case .page(let done, let total) = event {
                progress.page(file: name, done: done, total: total)
            }
        }
        return await monitor.wait()
    }

    /// Slots are flocks, so another run's files count too, and a crashed holder frees its slot.
    private static func acquireFileSlot(run: RunContext) async throws -> FileSlot? {
        let slots = try (0..<maximumFiles).map { index in
            try FileSlot(url: run.paths.slots.appendingPathComponent("file-\(index)"))
        }
        while !run.isCancelled {
            if let free = slots.first(where: { $0.tryLockExclusively() }) { return free }
            try? await Task.sleep(nanoseconds: slotPollNanoseconds)
        }
        return nil
    }
}

/// Hands out file indices and keeps results, in input order.
private actor FileQueue {
    private var next = 0
    private let count: Int
    private var stored: [Int: FileOutcome] = [:]

    init(count: Int) {
        self.count = count
    }

    func take() -> Int? {
        guard next < count else { return nil }
        defer { next += 1 }
        return next
    }

    func store(_ outcome: FileOutcome, at index: Int) {
        stored[index] = outcome
    }

    func outcomes() -> [Int: FileOutcome] {
        stored
    }
}

/// Everything the runner tasks share. Immutable, apart from the signal state behind a mutex.
private final class RunContext: Sendable {
    let request: RunRequest
    let paths: RuntimePaths
    let manifests: [JobManifest]
    let pidFiles: [URL]
    let jobLock: URL
    let jobStart: Date
    let log: ConversionLog
    let progress: ProgressReporter

    private struct Signals {
        var isCancelled = false
        var children: Set<pid_t> = []
    }

    private let signals = Mutex(Signals())

    init(
        request: RunRequest,
        paths: RuntimePaths,
        manifests: [JobManifest],
        pidFiles: [URL],
        jobLock: URL,
        jobStart: Date,
        log: ConversionLog,
        progress: ProgressReporter
    ) {
        self.request = request
        self.paths = paths
        self.manifests = manifests
        self.pidFiles = pidFiles
        self.jobLock = jobLock
        self.jobStart = jobStart
        self.log = log
        self.progress = progress
    }

    var isCancelled: Bool { signals.withLock { $0.isCancelled } }

    func register(child: pid_t, index: Int) {
        try? Data("\(child)\n".utf8).write(to: pidFiles[index])
        signals.withLock { state in
            state.children.insert(child)
            if state.isCancelled { kill(child, SIGKILL) }
        }
    }

    func unregister(child: pid_t) {
        _ = signals.withLock { $0.children.remove(child) }
    }

    /// SIGKILL, because children hold nothing to save: all they've written is in their manifest,
    /// which this process cleans. Measured: a child kept converting after a SIGTERM.
    func cancel() {
        signals.withLock { state in
            state.isCancelled = true
            for child in state.children { kill(child, SIGKILL) }
        }
    }

    func report(_ outcome: FileOutcome) {
        log.append(outcome)
        let name = outcome.input.lastPathComponent
        if let error = outcome.error {
            progress.line("failed: \(name): \(error)")
            return
        }
        let output = outcome.output.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        progress.line("\(name) -> \(output)")
        if outcome.didFallBack, let path = outcome.output {
            progress.line("  folder not writable, saved to \(path)")
        }
        if request.isVerbose {
            let stats = outcome.stats
            let rate = String(format: "%.1f", stats.traceMatchRate * 100)
            progress.line(
                "  pages \(stats.pages), OCR \(stats.ocrPages), tables \(stats.tables), "
                    + "images \(stats.images), math \(stats.mathSpans), "
                    + "font match \(rate)%, \(String(format: "%.1f", outcome.duration))s"
            )
        }
    }

    /// SIGINT and SIGTERM stop the children, and the run then cleans up like any failure.
    func handleSignals() -> [any DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [self] in cancel() }
            source.resume()
            return source
        }
    }
}

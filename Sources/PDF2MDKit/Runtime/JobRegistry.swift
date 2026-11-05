import Darwin
import Foundation

/// A write-ahead list of the paths one file's conversion may create, so whoever cleans up (the
/// supervisor, `--cancel`, or a later run's sweep) knows them even if the writer died.
public struct JobManifest: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func record(_ paths: [URL]) throws {
        try append(paths.map { "+" + Self.encoded($0.path) })
    }

    public func forget(_ paths: [URL]) throws {
        try append(paths.map { "-" + Self.encoded($0.path) })
    }

    /// Paths recorded and not retracted. An unreadable manifest means nothing to clean.
    public func entries() -> [URL] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var live: [String] = []
        for line in text.split(separator: "\n") {
            guard let path = line.dropFirst().removingPercentEncoding else { continue }
            if line.first == "+" {
                if !live.contains(path) { live.append(path) }
            } else if line.first == "-" {
                live.removeAll { $0 == path }
            }
        }
        return live.map { URL(fileURLWithPath: $0) }
    }

    public func remove() {
        unlink(url.path)
    }

    /// One path per line, whatever its name contains. A newline is legal in a file name.
    private static func encoded(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private func append(_ lines: [String]) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw ConversionFailure("couldn't write the job manifest")
        }
        defer { close(descriptor) }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == data.count else {
            throw ConversionFailure("couldn't write the job manifest")
        }
    }
}

/// Removes what an interrupted conversion left, and nothing else (A10).
public enum PartialOutput {
    public static let temporarySuffix = ".pdf2md-tmp"
    private static let assetsSuffix = "_assets"
    private static let markdownSuffix = ".md"

    /// Temp files and spools always go. A placeholder goes only while it has zero bytes, because
    /// a committed file is never empty. Its assets go only if the placeholder wasn't committed.
    /// Manifests are written ahead, so a crash can name a path that lost its reservation to a
    /// file that already existed. `createdSince` protects those: older paths aren't this job's.
    public static func clean(_ paths: [URL], caches: URL, createdSince: Date? = nil) {
        let manager = FileManager.default
        var isCommitted = false
        for url in paths where url.path.hasSuffix(markdownSuffix) {
            let attributes = try? manager.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int
            if size == 0, isOwn(attributes, createdSince: createdSince) {
                unlink(url.path)
            } else if size != nil {
                isCommitted = true
            }
        }
        for url in paths {
            if url.path.hasSuffix(temporarySuffix) {
                unlink(url.path)
            } else if url.path.hasPrefix(caches.path + "/") {
                try? manager.removeItem(at: url)
            } else if url.path.hasSuffix(assetsSuffix), !isCommitted,
                isOwn(try? manager.attributesOfItem(atPath: url.path), createdSince: createdSince)
            {
                removeOwnFiles(in: url)
            }
        }
    }

    /// Timestamps on some volumes round down by up to two seconds.
    private static let timestampSlack = 2.0

    private static func isOwn(_ attributes: [FileAttributeKey: Any]?, createdSince: Date?) -> Bool {
        guard let createdSince else { return true }
        guard let created = attributes?[.creationDate] as? Date else { return false }
        return created.timeIntervalSince(createdSince) >= -timestampSlack
    }

    /// Only names this tool generates, then `rmdir`, which fails if anything else is inside.
    private static func removeOwnFiles(in assets: URL) {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: assets.path)) ?? []
        for name in names where name.wholeMatch(of: /p\d{4,}-\d{2,}\.(png|jpg)/) != nil {
            unlink(assets.appendingPathComponent(name).path)
        }
        rmdir(assets.path)
    }
}

/// One supervised run: a directory holding a lock and one manifest per file.
///
/// The supervisor and its children hold `job.lock` shared, so the lock is free exactly when none
/// of them is alive, whatever way they ended (ADR-0007).
public final class JobHandle {
    private static let lockName = "job.lock"
    private static let pidName = "supervisor.pid"

    public let directory: URL
    private let lock: FileSlot

    /// Built under a dot name and renamed once locked, so a concurrent sweep never mistakes a job
    /// that is starting for a stale one.
    public init(paths: RuntimePaths) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: paths.jobs, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let building = paths.jobs.appendingPathComponent(".new-\(identifier)", isDirectory: true)
        try manager.createDirectory(at: building, withIntermediateDirectories: false)
        let lock = try FileSlot(url: building.appendingPathComponent(Self.lockName))
        lock.lockShared()
        try Data("\(getpid())\n".utf8).write(to: building.appendingPathComponent(Self.pidName))
        let final = paths.jobs.appendingPathComponent(identifier, isDirectory: true)
        try manager.moveItem(at: building, to: final)
        self.directory = final
        self.lock = lock
    }

    public var lockURL: URL { directory.appendingPathComponent(Self.lockName) }

    public func manifest(forFile index: Int) -> JobManifest {
        JobManifest(url: directory.appendingPathComponent("file-\(index).manifest"))
    }

    public func childPIDFile(forFile index: Int) -> URL {
        directory.appendingPathComponent("file-\(index).pid")
    }

    public func finish() {
        lock.unlock()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Cleans every job whose processes are all gone, as after a crash, kill or power loss.
    public static func sweepStale(paths: RuntimePaths) {
        for job in existingJobs(paths: paths) {
            guard let lock = try? FileSlot(url: job.appendingPathComponent(lockName)),
                lock.tryLockExclusively()
            else { continue }
            clean(job: job, paths: paths)
            lock.unlock()
        }
    }

    static func existingJobs(paths: RuntimePaths) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.jobs.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.map {
            paths.jobs.appendingPathComponent($0, isDirectory: true)
        }
    }

    static func clean(job: URL, paths: RuntimePaths) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: job.path)) ?? []
        let attributes = try? FileManager.default.attributesOfItem(atPath: job.path)
        let started = attributes?[.creationDate] as? Date
        for name in names where name.hasSuffix(".manifest") {
            let manifest = JobManifest(url: job.appendingPathComponent(name))
            PartialOutput.clean(manifest.entries(), caches: paths.caches, createdSince: started)
        }
        try? FileManager.default.removeItem(at: job)
    }
}

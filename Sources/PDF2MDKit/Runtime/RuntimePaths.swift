import Foundation

/// Where the tool keeps its own files. `PDF2MD_HOME` moves everything, for tests and e2e runs.
public struct RuntimePaths: Sendable, Equatable {
    public var slots: URL
    public var jobs: URL
    public var caches: URL
    public var log: URL
    public var downloads: URL

    public init(slots: URL, jobs: URL, caches: URL, log: URL, downloads: URL) {
        self.slots = slots
        self.jobs = jobs
        self.caches = caches
        self.log = log
        self.downloads = downloads
    }

    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RuntimePaths {
        if let override = environment["PDF2MD_HOME"], !override.isEmpty {
            return under(
                URL(fileURLWithPath: override, isDirectory: true),
                environment: environment
            )
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support/pdf2md")
        return RuntimePaths(
            slots: support.appendingPathComponent("slots"),
            jobs: support.appendingPathComponent("jobs"),
            caches: home.appendingPathComponent("Library/Caches/pdf2md"),
            log: home.appendingPathComponent("Library/Logs/pdf2md/pdf2md.log"),
            downloads: downloads(home: home, environment: environment)
        )
    }

    public static func under(
        _ root: URL,
        environment: [String: String] = [:]
    ) -> RuntimePaths {
        RuntimePaths(
            slots: root.appendingPathComponent("slots"),
            jobs: root.appendingPathComponent("jobs"),
            caches: root.appendingPathComponent("caches"),
            log: root.appendingPathComponent("logs/pdf2md.log"),
            downloads: downloads(home: root, environment: environment)
        )
    }

    private static func downloads(home: URL, environment: [String: String]) -> URL {
        if let override = environment["PDF2MD_DOWNLOADS"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return home.appendingPathComponent("Downloads", isDirectory: true)
    }
}

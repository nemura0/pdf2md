import CoreGraphics
import Foundation

/// The numbers one conversion reports, for the log and `--verbose`.
public struct ConversionStats: Sendable, Codable, Equatable {
    public var pages = 0
    public var ocrPages = 0
    public var tables = 0
    public var images = 0
    public var mathSpans = 0
    public var failedPages = 0
    public var matchedWords = 0
    public var unmatchedWords = 0

    public init() {}

    /// Share of words whose font came from the content stream. See ADR-0003.
    public var traceMatchRate: Double {
        let total = matchedWords + unmatchedWords
        return total == 0 ? 1 : Double(matchedWords) / Double(total)
    }
}

/// The result of converting one PDF.
public struct ConversionReport: Sendable, Codable, Equatable {
    public var output: String
    public var didFallBack: Bool
    public var stats: ConversionStats

    public init(output: String, didFallBack: Bool, stats: ConversionStats) {
        self.output = output
        self.didFallBack = didFallBack
        self.stats = stats
    }
}

/// Converts one PDF: workers extract pages to the spool, then one sequential pass writes Markdown.
/// It doesn't know whether it runs in a child process.
public struct DocumentConverter: Sendable {
    public struct Context: Sendable {
        public var paths: RuntimePaths
        public var jobs: Int
        public var spoolDirectory: URL
        public var now: @Sendable () -> Date
        public var onOpening: @Sendable () -> Void
        public var onStarted: @Sendable (Int) -> Void
        public var onPage: @Sendable (Int, Int) -> Void
        /// Called with every path before it is created, so a crash can't orphan one.
        public var recordPaths: @Sendable ([URL]) throws -> Void
        /// Retracts recorded paths that turned out to belong to someone else.
        public var forgetPaths: @Sendable ([URL]) throws -> Void

        public init(
            paths: RuntimePaths,
            jobs: Int,
            spoolDirectory: URL,
            now: @escaping @Sendable () -> Date = { Date() },
            onOpening: @escaping @Sendable () -> Void = {},
            onStarted: @escaping @Sendable (Int) -> Void = { _ in },
            onPage: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
            recordPaths: @escaping @Sendable ([URL]) throws -> Void = { _ in },
            forgetPaths: @escaping @Sendable ([URL]) throws -> Void = { _ in }
        ) {
            self.paths = paths
            self.jobs = jobs
            self.spoolDirectory = spoolDirectory
            self.now = now
            self.onOpening = onOpening
            self.onStarted = onStarted
            self.onPage = onPage
            self.recordPaths = recordPaths
            self.forgetPaths = forgetPaths
        }
    }

    private let context: Context

    public init(context: Context) {
        self.context = context
    }

    public func convert(pdf: URL, options: ConvertOptions) async throws -> ConversionReport {
        try Preflight.materialize(pdf)
        context.onOpening()
        let summary = try Preflight.open(pdf)
        try context.recordPaths([context.spoolDirectory])
        let reserved = try OutputWriter.reserve(
            pdf: pdf,
            options: options,
            downloads: context.paths.downloads,
            beforeCreating: context.recordPaths,
            didAbandon: context.forgetPaths
        )
        context.onStarted(summary.pageCount)
        let spool = try PageSpool(directory: context.spoolDirectory)
        defer { spool.remove() }

        var stats = try await extractPages(
            pdf: pdf,
            pageCount: summary.pageCount,
            options: options,
            spool: spool
        )
        guard stats.failedPages < summary.pageCount else {
            throw ConversionFailure("no page could be read")
        }
        let images = try emit(
            pdf: pdf,
            summary: summary,
            options: options,
            spool: spool,
            reserved: reserved,
            stats: &stats
        )
        try OutputWriter.commit(reserved, images: images)
        return ConversionReport(
            output: reserved.markdown.path,
            didFallBack: reserved.didFallBack,
            stats: stats
        )
    }

    // MARK: Extract

    private actor PageQueue {
        private var next = 0
        private let count: Int
        private var done = 0

        init(count: Int) {
            self.count = count
        }

        func take() -> Int? {
            guard next < count else { return nil }
            defer { next += 1 }
            return next
        }

        func finishOne() -> Int {
            done += 1
            return done
        }
    }

    private func extractPages(
        pdf: URL,
        pageCount: Int,
        options: ConvertOptions,
        spool: PageSpool
    ) async throws -> ConversionStats {
        let queue = PageQueue(count: pageCount)
        let workerCount = min(max(context.jobs, 1), pageCount)
        return try await withThrowingTaskGroup(of: ConversionStats.self) { group in
            for index in 0..<workerCount {
                let worker = try PageWorker(
                    index: index,
                    url: pdf,
                    slotURL: context.paths.slots.appendingPathComponent("page-\(index)"),
                    options: options
                )
                group.addTask { [context] in
                    try await Self.runWorker(
                        worker,
                        queue: queue,
                        spool: spool,
                        pageCount: pageCount,
                        context: context
                    )
                }
            }
            var stats = ConversionStats()
            stats.pages = pageCount
            for try await part in group { stats.add(part) }
            return stats
        }
    }

    /// One bad page costs that page, not the document. It's spooled empty and counted.
    private static func runWorker(
        _ worker: PageWorker,
        queue: PageQueue,
        spool: PageSpool,
        pageCount: Int,
        context: Context
    ) async throws -> ConversionStats {
        var stats = ConversionStats()
        while let index = await queue.take() {
            try Task.checkCancellation()
            var record: PageRecord
            do {
                record = try await worker.extract(pageIndex: index)
                try spool.write(record)
            } catch {
                // Bad values can't be encoded either. If this write fails too, the disk is the
                // problem, and that is worth failing the file for.
                record = PageRecord(index: index, width: 0, height: 0, didFail: true)
                try spool.write(record)
                stats.failedPages += 1
            }
            stats.matchedWords += record.matchedWords
            stats.unmatchedWords += record.unmatchedWords
            if record.isOCR { stats.ocrPages += 1 }
            context.onPage(await queue.finishOne(), pageCount)
        }
        return stats
    }

    // MARK: Emit

    private func emit(
        pdf: URL,
        summary: PDFSummary,
        options: ConvertOptions,
        spool: PageSpool,
        reserved: ReservedOutput,
        stats: inout ConversionStats
    ) throws -> [(source: URL, name: String)] {
        let fileName = pdf.deletingPathExtension().lastPathComponent
        let profile = try buildProfile(
            pageCount: summary.pageCount,
            metadataTitle: summary.metadataTitle,
            fileName: fileName,
            spool: spool
        )
        var stream = try MarkdownStream(url: reserved.temporary)
        if options.includeFrontMatter {
            try stream.write(
                block: FrontMatter.render(
                    title: profile.title.text,
                    source: pdf.lastPathComponent,
                    pages: summary.pageCount,
                    converted: Self.isoDate(context.now()),
                    tool: "pdf2md \(PDF2MDVersion.current)"
                )
            )
        }
        try stream.write(block: "# " + InlineRenderer.escape(profile.title.text))

        var flow = PageFlow()
        let assembler = PageAssembler(profile: profile)
        for page in 0..<summary.pageCount {
            try autoreleasepool {
                let record = try spool.read(page: page)
                let blocks = assembler.blocks(for: record)
                try flow.write(
                    blocks,
                    pageMarker: options.includePageMarkers ? "<!-- page \(page + 1) -->" : nil,
                    to: &stream
                )
            }
        }
        try flow.finish(to: &stream)
        try stream.close()
        return []
    }

    private func buildProfile(
        pageCount: Int,
        metadataTitle: String?,
        fileName: String,
        spool: PageSpool
    ) throws -> DocumentProfile {
        var builder = ProfileBuilder(pageCount: pageCount)
        for page in 0..<pageCount {
            try autoreleasepool {
                let record = try spool.read(page: page)
                builder.add(
                    pageIndex: page,
                    pageSize: record.size,
                    lines: LineBuilder.lines(from: record.words),
                    images: record.figures
                )
            }
        }
        return builder.finish(metadataTitle: metadataTitle, fileName: fileName)
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

extension ConversionStats {
    mutating func add(_ other: ConversionStats) {
        ocrPages += other.ocrPages
        tables += other.tables
        images += other.images
        mathSpans += other.mathSpans
        failedPages += other.failedPages
        matchedWords += other.matchedWords
        unmatchedWords += other.unmatchedWords
    }
}

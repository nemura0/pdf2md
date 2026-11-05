import CoreGraphics
import Foundation
import PDFKit

/// Owns one `PDFDocument` and is the only code that touches it (A3).
///
/// An actor on its own serial queue. Its API is synchronous, so a suspended page can't have the
/// document swapped under it by reentrancy, and blocking on the page slot only holds this
/// worker's queue. The per-item autorelease pool of the queue doesn't release PDFKit's page
/// cache, so the document itself is reopened regularly (ADR-0006).
actor PageWorker {
    /// One open document grew 0.43 MB per page over 1500 pages (97 to 736 MB). Reopening every
    /// 100 stayed flat at 251 MB and wasn't slower (7.4 s vs 8.3 s).
    private static let recycleInterval = 100

    private let queue: DispatchSerialQueue
    private let url: URL
    private let slot: FileSlot?
    private let options: ConvertOptions
    private var document: PDFDocument?
    private var pagesSinceOpen = 0

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    init(index: Int, url: URL, slotURL: URL?, options: ConvertOptions) throws {
        self.queue = DispatchSerialQueue(
            label: "pdf2md.worker.\(index)",
            autoreleaseFrequency: .workItem
        )
        self.url = url
        self.slot = try slotURL.map(FileSlot.init(url:))
        self.options = options
    }

    /// Extracts one page, holding the page slot throughout.
    func extract(pageIndex: Int) throws -> PageRecord {
        slot?.lockExclusively()
        defer { slot?.unlock() }
        return try autoreleasepool {
            let document = try currentDocument()
            guard let page = document.page(at: pageIndex), let pageRef = page.pageRef else {
                throw ConversionFailure("page \(pageIndex + 1) couldn't be read")
            }
            let geometry = DisplayGeometry(page: page)
            let trace = ContentStreamScanner.scan(page: pageRef, geometry: geometry)
            let text = PDFTextExtractor.extract(page: page, trace: trace, geometry: geometry)
            return PageRecord(
                index: pageIndex,
                width: geometry.size.width,
                height: geometry.size.height,
                words: text.words,
                figures: [],
                rules: trace.rules,
                matchedWords: text.matched,
                unmatchedWords: text.unmatched
            )
        }
    }

    private func currentDocument() throws -> PDFDocument {
        if pagesSinceOpen >= Self.recycleInterval {
            autoreleasepool { document = nil }
            pagesSinceOpen = 0
        }
        pagesSinceOpen += 1
        if let document { return document }
        guard let opened = PDFDocument(url: url) else {
            throw ConversionFailure("corrupt or unreadable PDF")
        }
        document = opened
        return opened
    }
}

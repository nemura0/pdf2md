import CoreGraphics
import Foundation
import PDFKit

/// A page between its two worker steps. Holds no PDFKit type, so it can cross to Vision.
struct PreparedPage: @unchecked Sendable {
    var record: PageRecord
    /// Set when Vision should look at this page. `CGImage` is immutable.
    var image: CGImage?
    var needsOCR: Bool
}

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
    /// A word's box is tighter than its ink: parentheses and summation limits reach past it.
    private static let equationPadding = 4.0

    private let queue: DispatchSerialQueue
    private let url: URL
    private let slot: FileSlot?
    private let options: ConvertOptions
    private let cropDirectory: URL?
    private var cropNames: [String: String] = [:]
    private var document: PDFDocument?
    private var pagesSinceOpen = 0

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    init(
        index: Int,
        url: URL,
        slotURL: URL?,
        options: ConvertOptions,
        cropDirectory: URL?
    ) throws {
        self.queue = DispatchSerialQueue(
            label: "pdf2md.worker.\(index)",
            autoreleaseFrequency: .workItem
        )
        self.url = url
        self.slot = try slotURL.map(FileSlot.init(url:))
        self.options = options
        self.cropDirectory = cropDirectory
    }

    /// Extracts a page and renders it if Vision is needed. Takes the page slot. `finish` must
    /// follow unless this throws, so the slot stays held while Vision works on the page.
    func prepare(pageIndex: Int) throws -> PreparedPage {
        slot?.lockExclusively()
        do {
            return try autoreleasepool { try read(pageIndex: pageIndex) }
        } catch {
            slot?.unlock()
            throw error
        }
    }

    func finish(
        _ prepared: PreparedPage,
        recognized: RecognizedPage?,
        failure: String?
    ) -> PageRecord {
        defer { slot?.unlock() }
        var record = PageRecognition.applying(
            recognized,
            to: prepared.record,
            needsOCR: prepared.needsOCR
        )
        record.note = record.note ?? failure
        return record
    }

    private func read(pageIndex: Int) throws -> PreparedPage {
        let document = try currentDocument()
        guard let page = document.page(at: pageIndex), let pageRef = page.pageRef else {
            throw ConversionFailure("page \(pageIndex + 1) couldn't be read")
        }
        let geometry = DisplayGeometry(page: page)
        let trace = ContentStreamScanner.scan(page: pageRef, geometry: geometry)
        let text = PDFTextExtractor.extract(page: page, trace: trace, geometry: geometry)
        var record = PageRecord(
            index: pageIndex,
            width: geometry.size.width,
            height: geometry.size.height,
            words: text.words + VectorBullets.words(marks: trace.marks, text: text.words),
            figures: [],
            rules: trace.rules,
            matchedWords: text.matched,
            unmatchedWords: text.unmatched
        )
        let plan = PageRecognition.plan(
            for: record,
            rules: trace.rules,
            figures: trace.figures,
            mode: options.ocrMode
        )
        let figures =
            options.includeImages
            ? FigureFilter.kept(trace.figures, pageSize: geometry.size, isOCR: plan.needsOCR)
            : []
        // OCR text is too rough to tell a stack of formulas from anything else.
        let stacked =
            plan.needsOCR
            ? []
            : StackedEquations.find(
                in: LineBuilder.lines(from: text.words),
                rules: trace.rules
            )
        let needsRender =
            plan.usesVision || figures.contains { cropNames[$0.digest] == nil }
            || (options.includeImages && !stacked.isEmpty)
        let rendered = needsRender ? PageRenderer.render(page, size: geometry.size) : nil
        record.figures = cropped(figures, from: rendered, note: &record.note)
        record.equations = cropped(
            stacked,
            pageIndex: pageIndex,
            from: rendered,
            note: &record.note
        )
        return PreparedPage(
            record: record,
            image: plan.usesVision ? rendered?.image : nil,
            needsOCR: plan.needsOCR
        )
    }

    /// One image is cropped once by this worker, however often it appears. A logo repeated on
    /// every page is cropped here too, since only emit knows that it repeats.
    private func cropped(
        _ figures: [FigureCandidate],
        from rendered: RenderedPage?,
        note: inout String?
    ) -> [FigureCandidate] {
        guard let cropDirectory else { return figures }
        return figures.map { figure in
            var result = figure
            if let known = cropNames[figure.digest] {
                result.cropFile = known
            } else if let rendered {
                result.cropFile = crop(
                    rendered,
                    rect: figure.rect,
                    isPhoto: figure.isPhoto,
                    name: figure.digest,
                    directory: cropDirectory,
                    note: &note
                )
                cropNames[figure.digest] = result.cropFile
            }
            return result
        }
    }

    private func cropped(
        _ equations: [StackedEquation],
        pageIndex: Int,
        from rendered: RenderedPage?,
        note: inout String?
    ) -> [EquationCrop] {
        equations.enumerated().map { offset, equation in
            var result = EquationCrop(rect: equation.rect, latex: equation.linearLatex)
            if let rendered, let cropDirectory, options.includeImages {
                result.cropFile = crop(
                    rendered,
                    rect: equation.rect.insetBy(
                        dx: -Self.equationPadding,
                        dy: -Self.equationPadding
                    ),
                    isPhoto: false,
                    name: "equation-\(pageIndex)-\(offset)",
                    directory: cropDirectory,
                    note: &note
                )
            }
            return result
        }
    }

    /// A crop that can't be written costs that image, never the page's text.
    private func crop(
        _ rendered: RenderedPage,
        rect: CGRect,
        isPhoto: Bool,
        name: String,
        directory: URL,
        note: inout String?
    ) -> String? {
        do {
            return try CropWriter.write(
                rendered,
                rect: rect,
                isPhoto: isPhoto,
                name: name,
                directory: directory
            )
        } catch {
            note = note ?? "an image was skipped: \(error.localizedDescription)"
            return nil
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

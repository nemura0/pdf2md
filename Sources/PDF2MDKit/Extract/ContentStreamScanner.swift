import CoreGraphics
import CryptoKit
import Foundation

/// One show operation, in display space.
struct TextRun {
    var originX: Double
    var endX: Double
    var baseline: Double
    var size: Double
    var style: FontStyle
    var isHorizontal: Bool
    /// False when the font has no widths, so `endX` is only an estimate.
    var hasReliableEnd: Bool
}

/// Everything one pass over a page's content stream finds.
struct PageTrace {
    var runs: [TextRun] = []
    var figures: [FigureCandidate] = []
    var rules: [RuleSegment] = []
    /// Small filled squares, in display space. Often they're a list's bullets.
    var marks: [CGRect] = []
    var hasPaintedPaths = false

    /// Nothing drawn at all, the kind of page LaTeX leaves before a chapter.
    var isBlank: Bool { runs.isEmpty && figures.isEmpty && !hasPaintedPaths }
}

/// Walks a page's content stream, tracking the CTM and text state. It reads font facts, image
/// placements and rules directly from the PDF, because PDFKit reports `Helvetica` for fonts that
/// aren't installed on the Mac (measured: ADR-0003). It never decodes glyphs to Unicode: PDFKit
/// does that.
enum ContentStreamScanner {
    static func scan(page: CGPDFPage, geometry: DisplayGeometry) -> PageTrace {
        let state = ScanState(geometry: geometry, resources: inheritedResources(of: page))
        let table = makeOperatorTable()
        state.currentTable = table
        let info = Unmanaged.passUnretained(state).toOpaque()
        let contents = CGPDFContentStreamCreateWithPage(page)
        let scanner = CGPDFScannerCreate(contents, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(contents)
        CGPDFOperatorTableRelease(table)
        return state.trace
    }

    /// `/Resources` can sit on any ancestor in the page tree.
    private static func inheritedResources(of page: CGPDFPage) -> CGPDFDictionaryRef? {
        var node = page.dictionary
        var depth = 0
        while let current = node, depth < ScanState.maximumFormDepth * 8 {
            if let resources = PDFValues.dictionary(current, "Resources") { return resources }
            node = PDFValues.dictionary(current, "Parent")
            depth += 1
        }
        return nil
    }

    private static func makeOperatorTable() -> CGPDFOperatorTableRef {
        guard let table = CGPDFOperatorTableCreate() else {
            preconditionFailure("CGPDFOperatorTableCreate only fails when out of memory")
        }
        OperatorCallbacks.register(in: table)
        return table
    }
}

/// Mutable scanner state, passed through the C callbacks' info pointer.
final class ScanState {
    static let maximumFormDepth = 12
    /// Malformed or huge pages can't make the record grow without limit.
    private static let maximumRules = 4000
    /// Depth limits alone allow ten Forms calling ten Forms, twelve levels deep.
    private static let maximumFormsPerPage = 4096
    private static let maximumStateDepth = 512
    private static let minimumFigureSide = 24.0
    /// A wrapper Form draws a whole page background, so it isn't a figure itself.
    private static let pageSizedShare = 0.95
    private static let minimumFigurePathOps = 20
    /// Thicker than this, a filled rectangle is a shape rather than a rule.
    private static let maximumRuleThickness = 2.5
    private static let horizontalSlopeLimit = 0.2

    struct GraphicsState {
        var ctm: CGAffineTransform
        var font: ResolvedFont?
        var fontSize = 0.0
        var charSpacing = 0.0
        var wordSpacing = 0.0
        var horizontalScale = 1.0
        var leading = 0.0
        var rise = 0.0
    }

    var trace = PageTrace()
    var graphics: GraphicsState
    private var stack: [GraphicsState] = []
    private var droppedSaves = 0
    /// A Form can't restore past its own start, whatever unbalanced `Q`s it holds.
    private var stackFloor = 0
    private var formsDrawn = 0
    private var textMatrix = CGAffineTransform.identity
    private var lineMatrix = CGAffineTransform.identity
    private var fonts: [CGPDFDictionaryRef: ResolvedFont] = [:]
    private var digests: [CGPDFStreamRef: String] = [:]
    private var photoDigests: Set<String> = []
    private var activeForms: Set<CGPDFStreamRef> = []
    private var resourceStack: [CGPDFDictionaryRef]
    private let pageSize: CGSize

    // Path state.
    private var pathOps = 0
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    private var pendingSegments: [(CGPoint, CGPoint)] = []
    private var pendingRects: [CGRect] = []

    init(geometry: DisplayGeometry, resources: CGPDFDictionaryRef?) {
        self.graphics = GraphicsState(ctm: geometry.transform)
        self.pageSize = geometry.size
        self.resourceStack = resources.map { [$0] } ?? []
    }

    // MARK: Graphics state

    func save() {
        if stack.count < Self.maximumStateDepth {
            stack.append(graphics)
        } else {
            droppedSaves += 1
        }
    }

    /// Past the depth cap, a `Q` only undoes a dropped `q`, or every later state would be wrong.
    func restore() {
        if droppedSaves > 0 {
            droppedSaves -= 1
        } else if stack.count > stackFloor, let last = stack.popLast() {
            graphics = last
        }
    }

    func concatenate(_ matrix: CGAffineTransform) {
        graphics.ctm = matrix.concatenating(graphics.ctm)
    }

    // MARK: Text state

    func beginText() {
        textMatrix = .identity
        lineMatrix = .identity
    }

    func setTextMatrix(_ matrix: CGAffineTransform) {
        textMatrix = matrix
        lineMatrix = matrix
    }

    func nextLine(_ x: Double, _ y: Double) {
        lineMatrix = CGAffineTransform(translationX: x, y: y).concatenating(lineMatrix)
        textMatrix = lineMatrix
    }

    func nextLineUsingLeading() {
        nextLine(0, -graphics.leading)
    }

    func setFont(named name: UnsafePointer<CChar>, size: Double, scanner: CGPDFScannerRef) {
        graphics.fontSize = size
        guard let stream = CGPDFScannerGetContentStream(scanner) as CGPDFContentStreamRef?,
            let object = CGPDFContentStreamGetResource(stream, "Font", name)
        else {
            graphics.font = nil
            return
        }
        var dictionary: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else {
            graphics.font = nil
            return
        }
        if let known = fonts[dictionary] {
            graphics.font = known
        } else {
            let resolved = ResolvedFont(dictionary: dictionary)
            fonts[dictionary] = resolved
            graphics.font = resolved
        }
    }

    // MARK: Show operations

    private struct PendingRun {
        var transform: CGAffineTransform
        var font: ResolvedFont
    }

    private var pendingRun: PendingRun?

    func beginShow() {
        guard let font = graphics.font else { return }
        let rise = CGAffineTransform(translationX: 0, y: graphics.rise)
        pendingRun = PendingRun(
            transform: rise.concatenating(textMatrix).concatenating(graphics.ctm),
            font: font
        )
    }

    func show(_ string: CGPDFStringRef) {
        guard let font = graphics.font, let bytes = CGPDFStringGetBytePtr(string) else { return }
        let length = CGPDFStringGetLength(string)
        var advance = 0.0
        var index = 0
        while index < length {
            let code: Int
            if font.isTwoByte, index + 1 < length {
                code = Int(bytes[index]) << 8 | Int(bytes[index + 1])
                index += 2
            } else {
                code = Int(bytes[index])
                index += 1
            }
            advance += font.advance(forCode: code) * graphics.fontSize + graphics.charSpacing
            if code == 32, !font.isTwoByte { advance += graphics.wordSpacing }
        }
        moveText(by: advance * graphics.horizontalScale)
    }

    /// A `TJ` number moves back by thousandths of the font size.
    func adjust(_ amount: Double) {
        moveText(by: -amount / 1000 * graphics.fontSize * graphics.horizontalScale)
    }

    private func moveText(by distance: Double) {
        guard distance.isFinite else { return }
        textMatrix = CGAffineTransform(translationX: distance, y: 0).concatenating(textMatrix)
    }

    func endShow() {
        guard let pending = pendingRun else { return }
        pendingRun = nil
        let matrix = pending.transform
        let origin = CGPoint.zero.applying(matrix)
        let rise = CGAffineTransform(translationX: 0, y: graphics.rise)
        let end = CGPoint.zero.applying(
            rise.concatenating(textMatrix).concatenating(graphics.ctm)
        )
        let size =
            graphics.fontSize * (matrix.c * matrix.c + matrix.d * matrix.d).squareRoot()
            * pending.font.sizeScale
        guard size.isFinite, size > 0, origin.x.isFinite, origin.y.isFinite else { return }
        let isHorizontal =
            abs(matrix.b) <= abs(matrix.a) * Self.horizontalSlopeLimit && matrix.a > 0
        trace.runs.append(
            TextRun(
                originX: origin.x,
                endX: end.x,
                baseline: origin.y,
                size: size,
                style: pending.font.style,
                isHorizontal: isHorizontal,
                hasReliableEnd: pending.font.hasReliableWidths
            )
        )
    }

    // MARK: XObjects

    func drawXObject(named name: UnsafePointer<CChar>, scanner: CGPDFScannerRef) {
        guard let contents = CGPDFScannerGetContentStream(scanner) as CGPDFContentStreamRef?,
            let object = CGPDFContentStreamGetResource(contents, "XObject", name)
        else { return }
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
            let dictionary = CGPDFStreamGetDictionary(stream)
        else { return }
        switch PDFValues.name(dictionary, "Subtype") {
        case "Image":
            addFigure(stream: stream, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        case "Form":
            drawForm(stream, dictionary: dictionary, parent: contents, table: currentTable)
        default:
            break
        }
    }

    /// Set by `OperatorCallbacks`, so nested Forms reuse the operator table.
    var currentTable: CGPDFOperatorTableRef?

    private func drawForm(
        _ stream: CGPDFStreamRef,
        dictionary: CGPDFDictionaryRef,
        parent: CGPDFContentStreamRef,
        table: CGPDFOperatorTableRef?
    ) {
        // Forms can reference themselves in a malformed file. Cut cycles and absurd depth.
        guard let table, activeForms.count < Self.maximumFormDepth,
            !activeForms.contains(stream), formsDrawn < Self.maximumFormsPerPage
        else { return }
        // CGPDFContentStreamCreateWithStream needs a resource dictionary. A Form without one
        // inherits from its parent, as old producers expect.
        let formResources = PDFValues.dictionary(dictionary, "Resources")
        guard let resources = formResources ?? resourceStack.last else { return }

        formsDrawn += 1
        activeForms.insert(stream)
        resourceStack.append(resources)
        let saved = (graphics, textMatrix, lineMatrix, stack.count, droppedSaves, stackFloor)
        stackFloor = stack.count
        if let matrix = PDFValues.array(dictionary, "Matrix"),
            let parsed = Self.matrix(from: matrix)
        {
            concatenate(parsed)
        }
        let box = PDFValues.array(dictionary, "BBox").flatMap(Self.rect(from:))
        let figuresBefore = trace.figures.count
        let pathOpsBefore = pathOps
        let formCTM = graphics.ctm

        scanForm(stream, resources: resources, parent: parent, table: table)

        if let box {
            addFormFigure(
                stream,
                dictionary: dictionary,
                rect: box.applying(formCTM),
                figuresBefore: figuresBefore,
                pathOps: pathOps - pathOpsBefore
            )
        }
        // Exactly the state from before the Form, even if its `q` and `Q` don't balance.
        (graphics, textMatrix, lineMatrix) = (saved.0, saved.1, saved.2)
        stack.removeLast(max(0, stack.count - saved.3))
        (droppedSaves, stackFloor) = (saved.4, saved.5)
        resourceStack.removeLast()
        activeForms.remove(stream)
    }

    private func scanForm(
        _ stream: CGPDFStreamRef,
        resources: CGPDFDictionaryRef,
        parent: CGPDFContentStreamRef,
        table: CGPDFOperatorTableRef
    ) {
        let inner = CGPDFContentStreamCreateWithStream(stream, resources, parent)
        let scanner = CGPDFScannerCreate(inner, table, Unmanaged.passUnretained(self).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(inner)
    }

    /// One figure for the whole Form, not one per piece inside it.
    private func addFormFigure(
        _ stream: CGPDFStreamRef,
        dictionary: CGPDFDictionaryRef,
        rect: CGRect,
        figuresBefore: Int,
        pathOps drawnOps: Int
    ) {
        let drewFigure = trace.figures.count > figuresBefore
        guard drewFigure || drawnOps >= Self.minimumFigurePathOps, isFigureSized(rect),
            !isPageSized(rect)
        else { return }
        trace.figures.removeSubrange(figuresBefore...)
        trace.figures.append(
            FigureCandidate(digest: formDigest(stream, dictionary: dictionary), rect: rect)
        )
    }

    func addInlineImage(stream: CGPDFStreamRef) {
        addFigure(stream: stream, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func addFigure(stream: CGPDFStreamRef, rect unit: CGRect) {
        let rect = unit.applying(graphics.ctm)
        guard isFigureSized(rect) else { return }
        let digest = streamDigest(stream)
        trace.figures.append(
            FigureCandidate(digest: digest, rect: rect, isPhoto: photoDigests.contains(digest))
        )
    }

    private func isFigureSized(_ rect: CGRect) -> Bool {
        rect.width >= Self.minimumFigureSide && rect.height >= Self.minimumFigureSide
            && rect.width.isFinite && rect.height.isFinite
    }

    private func isPageSized(_ rect: CGRect) -> Bool {
        rect.width >= pageSize.width * Self.pageSizedShare
            && rect.height >= pageSize.height * Self.pageSizedShare
    }

    // MARK: Digests

    /// A drawing on a transparent background can be all black, with the picture held entirely in
    /// its mask. Measured on a real book: figures with byte-identical pixels and different masks,
    /// which then shared one crop. So an image's identity covers its masks too.
    private func streamDigest(_ stream: CGPDFStreamRef) -> String {
        if let known = digests[stream] { return known }
        var format = CGPDFDataFormat.raw
        var hasher = SHA256()
        if let data = CGPDFStreamCopyData(stream, &format) {
            hasher.update(data: data as Data)
        }
        for mask in maskStreams(of: stream) {
            var maskFormat = CGPDFDataFormat.raw
            if let data = CGPDFStreamCopyData(mask, &maskFormat) {
                hasher.update(data: data as Data)
            }
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        digests[stream] = digest
        if format == .jpegEncoded || format == .JPEG2000 { photoDigests.insert(digest) }
        return digest
    }

    private func maskStreams(of stream: CGPDFStreamRef) -> [CGPDFStreamRef] {
        guard let dictionary = CGPDFStreamGetDictionary(stream) else { return [] }
        return ["SMask", "Mask"].compactMap { key in
            var mask: CGPDFStreamRef?
            return CGPDFDictionaryGetStream(dictionary, key, &mask) ? mask : nil
        }
    }

    /// Wrapper Forms such as `/Im0 Do` share bytes while showing different images, so a Form's
    /// identity also covers everything its resources reference.
    private func formDigest(_ stream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef) -> String {
        var pieces = [streamDigest(stream)]
        if let resources = PDFValues.dictionary(dictionary, "Resources"),
            let objects = PDFValues.dictionary(resources, "XObject")
        {
            pieces += nestedDigests(in: objects, depth: 0)
        }
        let joined = pieces.sorted().joined(separator: ",")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func nestedDigests(in objects: CGPDFDictionaryRef, depth: Int) -> [String] {
        guard depth < Self.maximumFormDepth else { return [] }
        var streams: [CGPDFStreamRef] = []
        withUnsafeMutablePointer(to: &streams) { pointer in
            CGPDFDictionaryApplyBlock(
                objects,
                { _, object, info in
                    var stream: CGPDFStreamRef?
                    if CGPDFObjectGetValue(object, .stream, &stream), let stream, let info {
                        info.assumingMemoryBound(to: [CGPDFStreamRef].self).pointee.append(stream)
                    }
                    return true
                },
                pointer
            )
        }
        var digests: [String] = []
        for stream in streams {
            digests.append(streamDigest(stream))
            if let dictionary = CGPDFStreamGetDictionary(stream),
                let resources = PDFValues.dictionary(dictionary, "Resources"),
                let nested = PDFValues.dictionary(resources, "XObject"), nested != objects
            {
                digests += nestedDigests(in: nested, depth: depth + 1)
            }
        }
        return digests
    }

    // MARK: Paths

    func moveTo(_ point: CGPoint) {
        pathOps += 1
        current = point
        subpathStart = point
    }

    func lineTo(_ point: CGPoint) {
        pathOps += 1
        if pendingSegments.count < Self.maximumRules { pendingSegments.append((current, point)) }
        current = point
    }

    func curveTo(_ point: CGPoint) {
        pathOps += 1
        current = point
    }

    func closePath() {
        if current != subpathStart, pendingSegments.count < Self.maximumRules {
            pendingSegments.append((current, subpathStart))
        }
        current = subpathStart
    }

    func addRect(_ rect: CGRect) {
        pathOps += 1
        if pendingRects.count < Self.maximumRules { pendingRects.append(rect) }
        current = rect.origin
        subpathStart = rect.origin
    }

    func paintPath(strokes: Bool, fills: Bool) {
        defer { clearPath() }
        if strokes || fills { trace.hasPaintedPaths = true }
        guard trace.rules.count < Self.maximumRules else { return }
        if strokes {
            for (start, end) in pendingSegments { addRule(start, end) }
            for rect in pendingRects { addRectEdges(rect) }
        } else if fills {
            for rect in pendingRects { addThinRect(rect) }
        }
    }

    func clearPath() {
        pendingSegments.removeAll(keepingCapacity: true)
        pendingRects.removeAll(keepingCapacity: true)
    }

    private func addRule(_ start: CGPoint, _ end: CGPoint) {
        let a = start.applying(graphics.ctm)
        let b = end.applying(graphics.ctm)
        guard trace.rules.count < Self.maximumRules, a.x.isFinite, a.y.isFinite, b.x.isFinite,
            b.y.isFinite
        else { return }
        let rule = RuleSegment(startX: a.x, startY: a.y, endX: b.x, endY: b.y)
        if rule.isHorizontal || rule.isVertical { trace.rules.append(rule) }
    }

    private func addRectEdges(_ rect: CGRect) {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        for index in corners.indices {
            addRule(corners[index], corners[(index + 1) % corners.count])
        }
    }

    /// Word processors draw rules as thin filled rectangles.
    private func addThinRect(_ rect: CGRect) {
        let display = rect.applying(graphics.ctm)
        guard trace.rules.count < Self.maximumRules, display.minX.isFinite, display.minY.isFinite,
            display.width.isFinite, display.height.isFinite
        else { return }
        if display.height <= Self.maximumRuleThickness, display.width > display.height {
            trace.rules.append(
                RuleSegment(
                    startX: display.minX,
                    startY: display.midY,
                    endX: display.maxX,
                    endY: display.midY
                )
            )
        } else if display.width <= Self.maximumRuleThickness, display.height > display.width {
            trace.rules.append(
                RuleSegment(
                    startX: display.midX,
                    startY: display.minY,
                    endX: display.midX,
                    endY: display.maxY
                )
            )
        } else if VectorBullets.isMarkShaped(display), trace.marks.count < Self.maximumRules {
            trace.marks.append(display)
        }
    }

    // MARK: Parsing helpers

    static func matrix(from array: CGPDFArrayRef) -> CGAffineTransform? {
        guard CGPDFArrayGetCount(array) == 6 else { return nil }
        let values = (0..<6).compactMap { PDFValues.number(array, $0) }
        guard values.count == 6 else { return nil }
        return CGAffineTransform(
            a: values[0],
            b: values[1],
            c: values[2],
            d: values[3],
            tx: values[4],
            ty: values[5]
        )
    }

    static func rect(from array: CGPDFArrayRef) -> CGRect? {
        guard CGPDFArrayGetCount(array) == 4 else { return nil }
        let values = (0..<4).compactMap { PDFValues.number(array, $0) }
        guard values.count == 4 else { return nil }
        return CGRect(
            x: values[0],
            y: values[1],
            width: values[2] - values[0],
            height: values[3] - values[1]
        )
    }
}

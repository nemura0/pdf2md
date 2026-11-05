import CoreGraphics
import Foundation

/// Turns one spooled page into blocks, applying the whole-document decisions from the profile.
struct PageAssembler {
    /// A few words over an image are its labels, already in the crop. Beyond this, it's text set
    /// over a picture, and the text is what the reader needs.
    private static let maximumFigureLabelWords = 30
    private static let largestLabelRatio = 1.1

    private let profile: DocumentProfile
    private let builder: BlockBuilder

    init(profile: DocumentProfile) {
        self.profile = profile
        self.builder = BlockBuilder(profile: profile)
    }

    func blocks(for record: PageRecord, namer: inout FigureNamer) -> [Block] {
        let content = LineBuilder.lines(from: record.words).filter { line in
            !profile.isRunningMargin(line, pageHeight: record.height)
                && !isTitleLine(line, in: record)
        }
        guard record.isSlide || !TableOfContents.isListing(content) else { return [] }
        let footnotes = footnotes(in: content, of: record)
        let lines = OutlineMatcher.marking(
            footnotes.lines,
            with: profile.outlineEntries(onPage: record.index),
            minimumSize: profile.minimumHeadingSize
        )
        let tables = record.tables.map {
            PageObject(rect: $0.rect, blocks: [.table($0.rows)], coversText: true)
        }
        let objects = ObjectPlacement.removingOverlaps(
            tables + equations(of: record, namer: &namer)
                + figures(of: record, lines: content, namer: &namer)
        )
        // Covered lines go first, since a table's rows would read as columns of text.
        let flowing = ObjectPlacement.removingCovered(lines, by: objects)
        var blocks: [Block] = []
        var hasText = false
        for segment in ObjectPlacement.segments(
            lines: ReadingOrder.order(flowing),
            objects: objects
        ) {
            switch segment {
            case .object(let object):
                blocks += object.blocks
            case .lines(let run):
                blocks += builder.blocks(
                    from: run,
                    isSlidePage: record.isSlide,
                    allowsSlideTitle: !hasText
                )
                hasText = true
            }
        }
        return blocks + footnotes.notes
    }

    /// Slides have no notes, and OCR has no fonts to tell a marker by.
    private func footnotes(in lines: [TextLine], of record: PageRecord) -> FootnotePage {
        guard !record.isSlide, !record.isOCR else { return FootnotePage(lines: lines, notes: []) }
        return Footnotes.separate(
            lines: lines,
            rules: record.rules,
            blockers: record.tables.map(\.rect) + record.figures.map(\.rect),
            pageIndex: record.index,
            bodySize: profile.bodySize,
            pageSize: record.size
        )
    }

    private func figures(
        of record: PageRecord,
        lines: [TextLine],
        namer: inout FigureNamer
    ) -> [PageObject] {
        record.figures.compactMap { figure in
            if figure.isDrawing {
                return drawing(figure, of: record, lines: lines, namer: &namer)
            }
            let isFirstCopy = !namer.hasCrop(for: figure.digest)
            guard let link = namer.link(for: figure, pageIndex: record.index) else { return nil }
            let inside = record.words.filter { word in
                figure.rect.contains(CGPoint(x: word.rect.midX, y: word.rect.midY))
            }
            // A reused crop was rendered from another page, so this page's text isn't in it. A
            // photo's overlaid text is meant to be read, not a chart's axis label.
            let holdsItsLabels =
                isFirstCopy && !figure.isPhoto && inside.count < Self.maximumFigureLabelWords
            return PageObject(
                rect: figure.rect,
                blocks: [.figure(path: link)],
                coversText: holdsItsLabels,
                largestCoveredSize: profile.bodySize * Self.largestLabelRatio
            )
        }
    }

    /// The picture holds the arrows, and its words stay readable for an LLM that only gets the text.
    /// With `--no-images` the words are all there is. A drawing that repeats is page furniture.
    private func drawing(
        _ figure: FigureCandidate,
        of record: PageRecord,
        lines: [TextLine],
        namer: inout FigureNamer
    ) -> PageObject {
        var blocks: [Block] = []
        if !namer.isRepeated(figure.digest) {
            if let link = namer.link(for: figure, pageIndex: record.index) {
                blocks.append(.figure(path: link))
            }
            let labels = DiagramLabels.lines(
                from: lines.filter { ObjectPlacement.isCovered($0, by: figure.rect) }
            )
            if !labels.isEmpty { blocks.append(.labels(labels)) }
        }
        return PageObject(rect: figure.rect, blocks: blocks, coversText: true)
    }

    /// The linear form and its picture, side by side: the form is searchable and cheap to read,
    /// and the picture holds the structure that the form loses (ADR-0005).
    private func equations(of record: PageRecord, namer: inout FigureNamer) -> [PageObject] {
        record.equations.enumerated().map { offset, equation in
            let image = FigureCandidate(
                digest: "equation-\(record.index)-\(offset)",
                rect: equation.rect,
                cropFile: equation.cropFile
            )
            let link = namer.link(for: image, pageIndex: record.index)
            let figure = link.map { [Block.figure(path: $0)] } ?? []
            return PageObject(
                rect: equation.rect,
                blocks: [.displayMath(equation.latex)] + figure,
                coversText: true
            )
        }
    }

    private func isTitleLine(_ line: TextLine, in record: PageRecord) -> Bool {
        record.index == 0 && profile.title.lineTexts.contains(line.text)
    }
}

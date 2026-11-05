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
        let lines = OutlineMatcher.marking(
            content,
            with: profile.outlineEntries(onPage: record.index),
            minimumSize: profile.minimumHeadingSize
        )
        let tables = record.tables.map {
            PageObject(rect: $0.rect, blocks: [.table($0.rows)], coversText: true)
        }
        let objects = ObjectPlacement.removingOverlaps(
            tables + equations(of: record, namer: &namer) + figures(of: record, namer: &namer)
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
        return blocks
    }

    private func figures(of record: PageRecord, namer: inout FigureNamer) -> [PageObject] {
        record.figures.compactMap { figure in
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

import CoreGraphics
import Foundation

/// Turns one spooled page into blocks, applying the whole-document decisions from the profile.
struct PageAssembler {
    private let profile: DocumentProfile
    private let builder: BlockBuilder

    init(profile: DocumentProfile) {
        self.profile = profile
        self.builder = BlockBuilder(profile: profile)
    }

    func blocks(for record: PageRecord) -> [Block] {
        let lines = LineBuilder.lines(from: record.words).filter { line in
            !profile.isRunningMargin(line, pageHeight: record.height)
                && !isTitleLine(line, in: record)
        }
        let objects = record.tables.map {
            PageObject(rect: $0.rect, blocks: [.table($0.rows)], coversText: true)
        }
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

    private func isTitleLine(_ line: TextLine, in record: PageRecord) -> Bool {
        record.index == 0 && profile.title.lineTexts.contains(line.text)
    }
}

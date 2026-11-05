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
        let isSlide = record.width > record.height * 1.1
        return builder.blocks(from: ReadingOrder.order(lines), isSlidePage: isSlide)
    }

    private func isTitleLine(_ line: TextLine, in record: PageRecord) -> Bool {
        record.index == 0 && profile.title.lineTexts.contains(line.text)
    }
}

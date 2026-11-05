import CoreGraphics
import Foundation

/// What a page needs from Vision, and how the answer changes its record.
enum PageRecognition {
    struct Plan: Equatable {
        var needsOCR: Bool
        var needsTables: Bool

        var usesVision: Bool { needsOCR || needsTables }
    }

    static func plan(
        for record: PageRecord,
        rules: [RuleSegment],
        figures: [FigureCandidate],
        mode: OCRMode
    ) -> Plan {
        let text = record.words.map(\.text).joined(separator: " ")
        let coverage = FigureFilter.imageCoverage(figures, pageSize: record.size)
        let needsOCR: Bool
        switch mode {
        case .always: needsOCR = true
        case .never: needsOCR = false
        case .auto: needsOCR = TextLayerQuality.needsOCR(text: text, pageImageCoverage: coverage)
        }
        // With no text and no OCR, a table's cells would have nothing to fill them.
        let needsTables =
            !record.words.isEmpty
            && (record.isSlide
                || TableHint.suggestsTable(
                    lines: LineBuilder.lines(from: record.words),
                    rules: rules,
                    pageWidth: record.width
                ))
        return Plan(needsOCR: needsOCR, needsTables: needsTables)
    }

    /// `recognized` is nil when Vision failed. A page that needed OCR then counts as failed. One
    /// that only wanted tables keeps its text as ordinary lines, which loses nothing.
    static func applying(
        _ recognized: RecognizedPage?,
        to record: PageRecord,
        needsOCR: Bool
    ) -> PageRecord {
        var result = record
        guard let recognized else {
            result.didFail = record.didFail || needsOCR
            return result
        }
        if needsOCR {
            result.words = RecognizedWords.words(from: recognized.lines, pageSize: record.size)
            result.isOCR = true
            result.matchedWords = 0
            result.unmatchedWords = 0
        }
        result.tables = recognized.tables.compactMap { table in
            TableGrid.rows(
                for: table,
                pageSize: record.size,
                words: needsOCR ? nil : record.words
            ).map { TableRegion(rect: table.rect.denormalized(to: record.size), rows: $0) }
        }
        return result
    }
}

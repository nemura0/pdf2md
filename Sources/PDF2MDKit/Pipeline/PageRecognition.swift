import CoreGraphics
import Foundation

/// What a page needs from Vision, and how the answer changes its record.
enum PageRecognition {
    private static let minimumCodeShare = 0.8

    struct Plan: Equatable {
        var needsOCR: Bool
        var needsTables: Bool

        var usesVision: Bool { needsOCR || needsTables }
    }

    static func plan(
        for record: PageRecord,
        rules: [RuleSegment],
        figures: [FigureCandidate],
        mode: OCRMode,
        isBlank: Bool = false
    ) -> Plan {
        let text = record.words.map(\.text).joined(separator: " ")
        let coverage = FigureFilter.imageCoverage(figures, pageSize: record.size)
        let needsOCR: Bool
        switch mode {
        case .always: needsOCR = true
        case .never: needsOCR = false
        // Vision can't read a page with nothing drawn on it, and the first use of Vision after an
        // install takes about 40 s. A book's blank pages were all it needed it for.
        case .auto:
            needsOCR =
                !isBlank && TextLayerQuality.needsOCR(text: text, pageImageCoverage: coverage)
        }
        let needsTables = needsTables(
            for: record,
            lines: LineBuilder.lines(from: record.words),
            rules: rules
        )
        return Plan(needsOCR: needsOCR, needsTables: needsTables)
    }

    /// With no text and no OCR, a table's cells would have nothing to fill them.
    static func needsTables(for record: PageRecord, lines: [TextLine], rules: [RuleSegment]) -> Bool
    {
        !record.words.isEmpty
            && (record.isSlide
                || TableHint.suggestsTable(lines: lines, rules: rules, pageWidth: record.width))
    }

    /// Vision takes two listings side by side for a table's columns. A real table has more than code.
    private static func isCode(_ rect: CGRect, words: [Word]) -> Bool {
        let inside = words.filter { rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
        let characters = inside.reduce(0) { $0 + $1.text.count }
        let code = inside.filter(\.font.isMonospace).reduce(0) { $0 + $1.text.count }
        return characters > 0 && Double(code) >= Double(characters) * minimumCodeShare
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
        // Vision found nothing, but the text layer may hold a stamp or a caption worth keeping.
        let hasOCRText = !recognized.lines.isEmpty || record.words.isEmpty
        if needsOCR, hasOCRText {
            result.words = RecognizedWords.words(from: recognized.lines, pageSize: record.size)
            result.isOCR = true
            result.matchedWords = 0
            result.unmatchedWords = 0
        }
        // Tables read from the page's rules are exact, and Vision takes a drawing's boxes for cells.
        let known = record.tables.map(\.rect) + record.figures.filter(\.isDrawing).map(\.rect)
        let recognizedTables = recognized.tables.compactMap { table in
            TableGrid.rows(
                for: table,
                pageSize: record.size,
                words: needsOCR && hasOCRText ? nil : record.words
            ).map { TableRegion(rect: table.rect.denormalized(to: record.size), rows: $0) }
        }
        result.tables =
            record.tables
            + recognizedTables.filter { table in
                !known.contains { $0.intersects(table.rect) }
                    && !isCode(table.rect, words: record.words)
            }
        return result
    }
}

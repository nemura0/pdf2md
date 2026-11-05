import CoreGraphics
import Vision

/// OCR and table structure from `RecognizeDocumentsRequest`, reduced to plain values. A new
/// process pays 0.44 s to load the model, then 0.15 s per page. The first load on a Mac takes
/// about 37 s (measured: ADR-0003).
public struct VisionDocumentRecognizer: DocumentRecognizing {
    private static let languages = [
        Locale.Language(identifier: "es-ES"), Locale.Language(identifier: "en-US"),
    ]

    public init() {}

    public func recognize(_ image: CGImage) async throws -> RecognizedPage {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = Self.languages
        request.textRecognitionOptions.useLanguageCorrection = true
        request.barcodeDetectionOptions.enabled = false

        let observations = try await request.perform(on: image)
        guard let document = observations.first?.document else {
            return RecognizedPage(lines: [], tables: [])
        }
        return RecognizedPage(
            lines: document.text.lines.compactMap(Self.line),
            tables: document.tables.map(Self.table)
        )
    }

    private static func line(_ observation: RecognizedTextObservation) -> RecognizedLine? {
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        return RecognizedLine(text: text, rect: topLeft(observation.boundingBox.cgRect))
    }

    private static func table(_ table: DocumentObservation.Container.Table) -> RecognizedTable {
        // A spanning cell is listed once per row it covers.
        var seen: Set<[Int]> = []
        var cells: [RecognizedCell] = []
        for cell in table.rows.joined() {
            let key = [
                cell.rowRange.lowerBound, cell.rowRange.upperBound, cell.columnRange.lowerBound,
                cell.columnRange.upperBound,
            ]
            guard seen.insert(key).inserted else { continue }
            cells.append(
                RecognizedCell(
                    text: cell.content.text.transcript,
                    rect: topLeft(cell.content.boundingRegion.boundingBox.cgRect),
                    rows: cell.rowRange,
                    columns: cell.columnRange
                )
            )
        }
        let box = topLeft(table.boundingRegion.boundingBox.cgRect)
        return RecognizedTable(rect: cells.reduce(box) { $0.union($1.rect) }, cells: cells)
    }

    /// Vision's normalized rects have their origin at the bottom left.
    private static func topLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}

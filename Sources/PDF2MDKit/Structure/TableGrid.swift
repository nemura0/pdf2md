import CoreGraphics
import Foundation

/// Turns Vision's table structure into rows of text. Vision reads structure well, and PDFKit text
/// is exact, so a page with a text layer takes the text from the words in each cell's region.
public enum TableGrid {
    private static let minimumRows = 2
    private static let minimumColumns = 2
    /// A grid this empty is a layout Vision mistook for a table, and reads better as text.
    private static let minimumFilledShare = 0.4
    private static let containmentTolerance = 2.0

    /// Rows of cell text, or nil if this isn't a credible table. `words` are in display space.
    /// Without words, cells keep the OCR text. Spanning cells fill their first position.
    public static func rows(
        for table: RecognizedTable,
        pageSize: CGSize,
        words: [Word]?
    ) -> [[String]]? {
        let rowCount = (table.cells.map(\.rows.upperBound).max() ?? -1) + 1
        let columnCount = (table.cells.map(\.columns.upperBound).max() ?? -1) + 1
        guard rowCount >= minimumRows, columnCount >= minimumColumns else { return nil }

        var grid = [[String]](
            repeating: [String](repeating: "", count: columnCount),
            count: rowCount
        )
        let cellWords = words.map { fill(table, pageSize: pageSize, words: $0) }
        for (index, cell) in table.cells.enumerated() {
            grid[cell.rows.lowerBound][cell.columns.lowerBound] =
                cellWords.map { text(from: $0[index]) }
                ?? InlineRenderer.escape(TextNormalizer.normalize(cell.text))
        }
        let filled = grid.joined().filter { !$0.isEmpty }.count
        guard Double(filled) >= Double(rowCount * columnCount) * minimumFilledShare else {
            return nil
        }
        return grid
    }

    /// Every word inside the table lands in the cell holding its center, or else the nearest one,
    /// since Vision's cells can leave gaps and a word must not vanish in one.
    private static func fill(
        _ table: RecognizedTable,
        pageSize: CGSize,
        words: [Word]
    ) -> [[Word]] {
        let rects = table.cells.map { $0.rect.denormalized(to: pageSize) }
        let outline = table.rect.denormalized(to: pageSize)
            .insetBy(dx: -containmentTolerance, dy: -containmentTolerance)
        var assigned = [[Word]](repeating: [], count: rects.count)
        for word in words {
            let center = CGPoint(x: word.rect.midX, y: word.rect.midY)
            guard outline.contains(center) else { continue }
            let holder =
                rects.firstIndex { $0.contains(center) }
                ?? rects.indices.min { distance(center, rects[$0]) < distance(center, rects[$1]) }
            if let holder { assigned[holder].append(word) }
        }
        return assigned
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        hypot(
            max(rect.minX - point.x, 0, point.x - rect.maxX),
            max(rect.minY - point.y, 0, point.y - rect.maxY)
        )
    }

    private static func text(from words: [Word]) -> String {
        LineBuilder.lines(from: words)
            .map { InlineRenderer.render($0.words) }
            .joined(separator: " ")
    }
}

extension CGRect {
    /// From page-normalized values to points.
    func denormalized(to size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

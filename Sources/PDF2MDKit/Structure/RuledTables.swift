import CoreGraphics
import Foundation

/// Reads tables drawn as a full grid of rules. The rules give the cells exactly, and the words
/// give the text, so a page like this needs no Vision pass. On a real book's page of three such
/// tables, Vision found two.
public enum RuledTables {
    /// Crossing rules leave gaps of about 0.4 points in LaTeX's `tabular`.
    private static let touchTolerance = 1.5
    private static let minimumColumns = 2
    private static let minimumRows = 2
    /// A band this thin holds no text. It's the space inside a double rule.
    private static let minimumRowHeight = 4.0
    /// A real frame's rules only break at their crossings, for less than this. Two boxes of a
    /// diagram side by side can cover 94% of a frame (measured on a real book), with one big gap.
    private static let largestFrameGap = 3.0
    /// A drawn array can have a row of indices above a row of empty cells.
    private static let minimumRowsWithText = 2
    /// A grid this empty is a drawing, as in `TableGrid`.
    private static let minimumFilledShare = 0.4
    /// A page of real tables has a few hundred. The search is quadratic, and past this it's art.
    private static let maximumRules = 1500
    /// The middle of a letter, above the baseline, in font sizes. Word boxes follow the font's
    /// bounding box and can reach the row above, so they can't place a word in a row.
    private static let letterMiddle = 0.3
    /// Superscripts sit about this far off their line.
    private static let sameLineTolerance = 4.5

    private struct Horizontal {
        var y: Double
        var minX: Double
        var maxX: Double
    }

    private struct Vertical {
        var x: Double
        var minY: Double
        var maxY: Double
    }

    /// Rules that touch, as one group. Each table has its own, however close the tables sit.
    private struct Group {
        var horizontals: [Horizontal] = []
        var verticals: [Vertical] = []
    }

    public static func find(rules: [RuleSegment], words: [Word]) -> [TableRegion] {
        guard rules.count <= maximumRules, !words.isEmpty else { return [] }
        return groups(of: rules).compactMap { table(from: $0, words: words) }
            .sorted { $0.rect.minY < $1.rect.minY }
    }

    // MARK: Grouping

    private static func groups(of rules: [RuleSegment]) -> [Group] {
        let horizontals = rules.filter(\.isHorizontal).map {
            Horizontal(y: $0.startY, minX: min($0.startX, $0.endX), maxX: max($0.startX, $0.endX))
        }
        let verticals = rules.filter(\.isVertical).map {
            Vertical(x: $0.startX, minY: min($0.startY, $0.endY), maxY: max($0.startY, $0.endY))
        }
        var parent = Array(0..<(horizontals.count + verticals.count))
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }
        for (first, horizontal) in horizontals.enumerated() {
            for (second, vertical) in verticals.enumerated()
            where touches(horizontal, vertical) {
                parent[root(first)] = root(horizontals.count + second)
            }
        }
        // LaTeX cuts a column line at each row of text, even with no rule across it there.
        for (first, upper) in verticals.enumerated() {
            for (second, lower) in verticals.enumerated().dropFirst(first + 1)
            where continues(upper, lower) {
                parent[root(horizontals.count + first)] = root(horizontals.count + second)
            }
        }
        var byRoot: [Int: Group] = [:]
        for (index, horizontal) in horizontals.enumerated() {
            byRoot[root(index), default: Group()].horizontals.append(horizontal)
        }
        for (index, vertical) in verticals.enumerated() {
            byRoot[root(horizontals.count + index), default: Group()].verticals.append(vertical)
        }
        return Array(byRoot.values)
    }

    private static func touches(_ horizontal: Horizontal, _ vertical: Vertical) -> Bool {
        vertical.x >= horizontal.minX - touchTolerance
            && vertical.x <= horizontal.maxX + touchTolerance
            && horizontal.y >= vertical.minY - touchTolerance
            && horizontal.y <= vertical.maxY + touchTolerance
    }

    private static func continues(_ first: Vertical, _ second: Vertical) -> Bool {
        abs(first.x - second.x) <= touchTolerance
            && first.minY <= second.maxY + touchTolerance
            && second.minY <= first.maxY + touchTolerance
    }

    // MARK: The grid

    private static func table(from group: Group, words: [Word]) -> TableRegion? {
        let columnLines = clusters(group.verticals.map(\.x))
        let rowLines = clusters(group.horizontals.map(\.y))
        guard columnLines.count > minimumColumns, rowLines.count > minimumRows,
            let left = columnLines.first, let right = columnLines.last,
            let top = rowLines.first, let bottom = rowLines.last,
            hasFrame(group, left: left, right: right, top: top, bottom: bottom)
        else { return nil }

        let bands = zip(rowLines, rowLines.dropFirst()).filter { $1 - $0 >= minimumRowHeight }
        let frame = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        let inside = words.filter { frame.contains(CGPoint(x: $0.rect.midX, y: middle(of: $0))) }
        let rows = bands.flatMap { band in
            rows(inBand: band, columnLines: columnLines, verticals: group.verticals, words: inside)
        }
        guard isFilled(rows) else { return nil }
        return TableRegion(rect: frame, rows: rows)
    }

    /// The rows between two rules. Usually one, but a table can rule only its header and end. When
    /// every column has text on each of the band's lines, those lines are its rows. Otherwise a
    /// long cell is wrapping next to a short one, and the band is one row.
    private static func rows(
        inBand band: (Double, Double),
        columnLines: [Double],
        verticals: [Vertical],
        words: [Word]
    ) -> [[String]] {
        let inBand = words.filter { middle(of: $0) >= band.0 && middle(of: $0) < band.1 }
        let whole = cells(band, columnLines: columnLines, verticals: verticals, words: inBand)
        let lines = clusters(inBand.map(\.baseline), tolerance: sameLineTolerance)
        guard lines.count > 1 else { return [whole] }
        let split = lines.map { baseline in
            cells(
                band,
                columnLines: columnLines,
                verticals: verticals,
                words: inBand.filter { abs($0.baseline - baseline) <= sameLineTolerance }
            )
        }
        let filledColumns = whole.filter { !$0.isEmpty }.count
        let isAligned = split.allSatisfy { row in
            row.filter { !$0.isEmpty }.count == filledColumns
        }
        return isAligned ? split : [whole]
    }

    private static func middle(of word: Word) -> Double {
        word.baseline - word.size * letterMiddle
    }

    /// Words go in the column holding their center. Where no rule separates two columns on this
    /// row, the cell spans them, and its text takes the first position with the rest left empty.
    private static func cells(
        _ row: (Double, Double),
        columnLines: [Double],
        verticals: [Vertical],
        words: [Word]
    ) -> [String] {
        var holders = Array(0..<(columnLines.count - 1))
        for column in 1..<holders.count {
            let spans = verticals.filter { abs($0.x - columnLines[column]) <= touchTolerance }
                .map { ($0.minY, $0.maxY) }
            let isRuled = coverage(of: spans, from: row.0, to: row.1) >= (row.1 - row.0) / 2
            if !isRuled { holders[column] = holders[column - 1] }
        }
        var assigned = [[Word]](repeating: [], count: holders.count)
        for word in words {
            let column = columnLines.lastIndex { $0 <= word.rect.midX } ?? 0
            assigned[holders[min(column, holders.count - 1)]].append(word)
        }
        return assigned.map(TableGrid.text(from:))
    }

    private static func isFilled(_ rows: [[String]]) -> Bool {
        guard rows.count >= minimumRows, let columnCount = rows.first?.count else { return false }
        let filled = rows.joined().filter { !$0.isEmpty }.count
        let hasEmptyColumn = (0..<columnCount).contains { column in
            rows.allSatisfy { $0[column].isEmpty }
        }
        let rowsWithText = rows.filter { row in row.contains { !$0.isEmpty } }.count
        return !hasEmptyColumn && rowsWithText >= minimumRowsWithText
            && Double(filled) >= Double(rows.count * columnCount) * minimumFilledShare
    }

    /// Top, bottom and both sides are ruled end to end.
    private static func hasFrame(
        _ group: Group,
        left: Double,
        right: Double,
        top: Double,
        bottom: Double
    ) -> Bool {
        let spansAt = { (y: Double) in
            group.horizontals.filter { abs($0.y - y) <= touchTolerance }.map { ($0.minX, $0.maxX) }
        }
        let spansOn = { (x: Double) in
            group.verticals.filter { abs($0.x - x) <= touchTolerance }.map { ($0.minY, $0.maxY) }
        }
        return largestGap(in: spansAt(top), from: left, to: right) <= largestFrameGap
            && largestGap(in: spansAt(bottom), from: left, to: right) <= largestFrameGap
            && largestGap(in: spansOn(left), from: top, to: bottom) <= largestFrameGap
            && largestGap(in: spansOn(right), from: top, to: bottom) <= largestFrameGap
    }

    private static func largestGap(
        in spans: [(Double, Double)],
        from start: Double,
        to end: Double
    ) -> Double {
        var gap = 0.0
        var reach = start
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            gap = max(gap, span.0 - reach)
            reach = max(reach, span.1)
        }
        return max(gap, end - reach)
    }

    private static func coverage(
        of spans: [(Double, Double)],
        from start: Double,
        to end: Double
    ) -> Double {
        var covered = 0.0
        var reach = start
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            let spanEnd = min(span.1, end)
            if spanEnd > reach {
                covered += spanEnd - max(span.0, reach)
                reach = spanEnd
            }
        }
        return covered
    }

    /// Positions within the tolerance count as one, at their average.
    private static func clusters(
        _ values: [Double],
        tolerance: Double = touchTolerance
    ) -> [Double] {
        var groups: [[Double]] = []
        for value in values.sorted() {
            if let last = groups.last?.last, value - last <= tolerance {
                groups[groups.count - 1].append(value)
            } else {
                groups.append([value])
            }
        }
        return groups.map { $0.reduce(0, +) / Double($0.count) }
    }
}

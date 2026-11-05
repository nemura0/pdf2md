import CoreGraphics
import Foundation

/// Decides whether a page's layout is worth a Vision table pass. A false positive costs 0.15 s,
/// and Vision still has to find a table, so this leans towards yes.
public enum TableHint {
    private static let minimumRows = 3
    private static let minimumCellsPerRow = 2
    private static let alignmentTolerance = 4.0
    private static let baselineTolerance = 2.0
    /// Cells are short. Two columns of prose fill most of their half of the page.
    private static let maximumCellShare = 0.33
    /// Booktabs tables have three horizontal rules and no vertical ones.
    private static let minimumHorizontalRules = 3
    private static let minimumVerticalRules = 2
    private static let ruleOverlapShare = 0.5
    private static let minimumRuleLength = 30.0

    public static func suggestsTable(
        lines: [TextLine],
        rules: [RuleSegment],
        pageWidth: Double
    ) -> Bool {
        hasRuledGrid(rules) || hasAlignedRows(lines, pageWidth: pageWidth)
    }

    private static func hasRuledGrid(_ rules: [RuleSegment]) -> Bool {
        let horizontal = rules.filter {
            $0.isHorizontal && abs($0.endX - $0.startX) >= minimumRuleLength
        }
        let rows = distinct(horizontal.map(\.startY))
        guard rows >= minimumHorizontalRules else { return false }
        let vertical = rules.filter { $0.isVertical }
        if distinct(vertical.map(\.startX)) >= minimumVerticalRules { return true }

        // Without verticals, rules that overlap are a table, and scattered ones are underlines.
        guard let longest = horizontal.max(by: { length($0) < length($1) }) else { return false }
        let overlapping = horizontal.filter { rule in
            let overlap =
                min(max(rule.startX, rule.endX), max(longest.startX, longest.endX))
                - max(min(rule.startX, rule.endX), min(longest.startX, longest.endX))
            return overlap >= length(longest) * ruleOverlapShare
        }
        return distinct(overlapping.map(\.startY)) >= minimumHorizontalRules
    }

    private static func length(_ rule: RuleSegment) -> Double {
        abs(rule.endX - rule.startX)
    }

    private static func distinct(_ values: [Double]) -> Int {
        var count = 0
        var last = -Double.infinity
        for value in values.sorted() where value - last > baselineTolerance {
            count += 1
            last = value
        }
        return count
    }

    /// Consecutive rows of short cells whose starts line up.
    private static func hasAlignedRows(_ lines: [TextLine], pageWidth: Double) -> Bool {
        let rows = groupByBaseline(lines)
        var run = 0
        var previous: [Double] = []
        for row in rows {
            let cells = row.sorted { $0.rect.minX < $1.rect.minX }
            let isTabular =
                cells.count >= minimumCellsPerRow
                && cells.allSatisfy { $0.rect.width <= pageWidth * maximumCellShare }
            guard isTabular else {
                run = 0
                previous = []
                continue
            }
            let starts = cells.map { Double($0.rect.minX) }
            run = run > 0 && aligned(starts, previous) >= minimumCellsPerRow ? run + 1 : 1
            previous = starts
            if run >= minimumRows { return true }
        }
        return false
    }

    private static func aligned(_ first: [Double], _ second: [Double]) -> Int {
        first.filter { value in second.contains { abs($0 - value) <= alignmentTolerance } }.count
    }

    private static func groupByBaseline(_ lines: [TextLine]) -> [[TextLine]] {
        var rows: [[TextLine]] = []
        for line in lines.sorted(by: { $0.baseline < $1.baseline }) {
            if let last = rows.last?.first, line.baseline - last.baseline <= baselineTolerance {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
    }
}

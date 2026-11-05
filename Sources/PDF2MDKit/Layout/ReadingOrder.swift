import CoreGraphics

/// Orders lines for reading: top to bottom, with two-column bands read left then right.
public enum ReadingOrder {
    private static let minimumLinesPerColumn = 3
    private static let minimumSharedRows = 2
    /// The gutter is looked for in the middle half of the text.
    private static let gutterSearchRange = 0.25...0.75
    private static let gutterStep = 2.0
    /// Lines crossing the gutter span both columns, like headings. They can't dominate a page.
    private static let maximumSpanningShare = 0.25
    private static let minimumSpanningAllowance = 2
    /// Columns hold real text. Short labels at the side of a page aren't a column.
    private static let minimumColumnWidthShare = 0.2

    public static func order(_ lines: [TextLine]) -> [TextLine] {
        let sorted = lines.sorted(by: isAbove)
        guard let gutter = findGutter(in: sorted) else { return sorted }

        var ordered: [TextLine] = []
        var left: [TextLine] = []
        var right: [TextLine] = []
        func flushBand() {
            if sharedRowCount(left, right) >= minimumSharedRows {
                ordered += left + right
            } else {
                ordered += (left + right).sorted(by: isAbove)
            }
            left = []
            right = []
        }
        for line in sorted {
            if line.rect.minX < gutter, line.rect.maxX > gutter {
                flushBand()
                ordered.append(line)
            } else if line.rect.maxX <= gutter {
                left.append(line)
            } else {
                right.append(line)
            }
        }
        flushBand()
        return ordered
    }

    private static func isAbove(_ first: TextLine, _ second: TextLine) -> Bool {
        let tolerance = min(first.size, second.size) * 0.3
        if abs(first.baseline - second.baseline) > tolerance {
            return first.baseline < second.baseline
        }
        return first.rect.minX < second.rect.minX
    }

    /// Picks the x with the fewest lines crossing it, then checks that what it separates really
    /// looks like two columns.
    private static func findGutter(in lines: [TextLine]) -> Double? {
        guard lines.count >= minimumLinesPerColumn * 2,
            let minX = lines.map(\.rect.minX).min(),
            let maxX = lines.map(\.rect.maxX).max()
        else { return nil }
        let textWidth = maxX - minX
        guard textWidth > 0 else { return nil }

        let start = minX + textWidth * gutterSearchRange.lowerBound
        let end = minX + textWidth * gutterSearchRange.upperBound
        var best: (x: Double, crossing: Int)?
        for x in stride(from: start, through: end, by: gutterStep) {
            let crossing = lines.filter { $0.rect.minX < x && $0.rect.maxX > x }.count
            if crossing < best?.crossing ?? Int.max { best = (x, crossing) }
        }
        guard let best else { return nil }
        let allowed = max(
            minimumSpanningAllowance,
            Int(Double(lines.count) * maximumSpanningShare)
        )
        guard best.crossing <= allowed else { return nil }

        let gutter = centerOfGap(around: best.x, in: lines)
        let left = lines.filter { $0.rect.maxX <= gutter }
        let right = lines.filter { $0.rect.minX >= gutter }
        guard left.count >= minimumLinesPerColumn, right.count >= minimumLinesPerColumn,
            averageWidth(left) >= textWidth * minimumColumnWidthShare,
            averageWidth(right) >= textWidth * minimumColumnWidthShare,
            sharedRowCount(left, right) >= minimumSharedRows
        else { return nil }
        return gutter
    }

    /// Centers on the empty strip, so a line ending just before the first candidate x stays left.
    private static func centerOfGap(around x: Double, in lines: [TextLine]) -> Double {
        let nonCrossing = lines.filter { !($0.rect.minX < x && $0.rect.maxX > x) }
        let leftEdge =
            nonCrossing.filter { $0.rect.maxX <= x }.map { Double($0.rect.maxX) }.max() ?? x
        let rightEdge =
            nonCrossing.filter { $0.rect.minX >= x }.map { Double($0.rect.minX) }.min() ?? x
        return (leftEdge + rightEdge) / 2
    }

    private static func averageWidth(_ lines: [TextLine]) -> Double {
        lines.isEmpty ? 0 : lines.map(\.rect.width).reduce(0, +) / Double(lines.count)
    }

    private static func sharedRowCount(_ left: [TextLine], _ right: [TextLine]) -> Int {
        left.filter { line in
            right.contains { other in
                min(line.rect.maxY, other.rect.maxY) > max(line.rect.minY, other.rect.minY)
            }
        }.count
    }
}

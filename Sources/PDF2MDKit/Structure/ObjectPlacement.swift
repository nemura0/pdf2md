import CoreGraphics
import Foundation

/// Something on a page that isn't running text: a table, a figure or an equation.
struct PageObject: Sendable, Equatable {
    var rect: CGRect
    var blocks: [Block]
    /// Text inside it is already part of the object, so it leaves the flow.
    var coversText: Bool
    /// Lines larger than this stay in the flow, since a label is never set above the body size.
    var largestCoveredSize = Double.infinity
}

enum PageSegment: Equatable {
    case lines([TextLine])
    case object(PageObject)
}

/// Places objects among a page's lines by position.
enum ObjectPlacement {
    /// Boxes from Vision and from image placements sit a little off the text they hold.
    private static let containmentTolerance = 2.0

    static func removingCovered(_ lines: [TextLine], by objects: [PageObject]) -> [TextLine] {
        let covering = objects.filter(\.coversText)
        guard !covering.isEmpty else { return lines }
        return lines.filter { line in
            !covering.contains { object in
                line.size <= object.largestCoveredSize && isCovered(line, by: object.rect)
            }
        }
    }

    static func isCovered(_ line: TextLine, by rect: CGRect) -> Bool {
        rect.insetBy(dx: -containmentTolerance, dy: -containmentTolerance)
            .contains(CGPoint(x: line.rect.midX, y: line.rect.midY))
    }

    /// Later objects that overlap an earlier one hold the same words, as when a ruled table of
    /// formulas is also seen as a stacked equation. `objects` come in priority order.
    static func removingOverlaps(_ objects: [PageObject]) -> [PageObject] {
        var kept: [PageObject] = []
        for object in objects {
            let center = CGPoint(x: object.rect.midX, y: object.rect.midY)
            let isOverlapped = kept.contains { other in
                other.coversText && other.rect.contains(center)
            }
            if !isOverlapped { kept.append(object) }
        }
        return kept
    }

    /// Each object goes before the first line, in reading order, that is below its top and shares
    /// some of its width. That holds inside a column, where a later line can be higher on the
    /// page. An object with nothing below it goes last.
    static func segments(lines: [TextLine], objects: [PageObject]) -> [PageSegment] {
        let sorted = objects.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
        var pending = [Int: [PageObject]]()
        for (object, slot) in zip(sorted, slots(of: sorted, among: lines)) {
            pending[slot, default: []].append(object)
        }

        var segments: [PageSegment] = []
        var run: [TextLine] = []
        for index in 0...lines.count {
            if let objects = pending[index] {
                if !run.isEmpty { segments.append(.lines(run)) }
                run = []
                segments += objects.map(PageSegment.object)
            }
            if index < lines.count { run.append(lines[index]) }
        }
        if !run.isEmpty { segments.append(.lines(run)) }
        return segments
    }

    /// Objects side by side go together, or a heading that only reaches one of them would land
    /// between them. In two columns, lines above an object come in between, and each keeps its own.
    private static func slots(of sorted: [PageObject], among lines: [TextLine]) -> [Int] {
        let own = sorted.map { object in
            lines.firstIndex { line in
                line.rect.midY > object.rect.minY
                    && line.rect.minX < object.rect.maxX && line.rect.maxX > object.rect.minX
            } ?? lines.count
        }
        var slots = own
        var start = 0
        while start < sorted.count {
            var bottom = sorted[start].rect.maxY
            var end = start + 1
            while end < sorted.count, sorted[end].rect.minY < bottom {
                bottom = max(bottom, sorted[end].rect.maxY)
                end += 1
            }
            let first = own[start..<end].min() ?? lines.count
            for index in start..<end where own[index] > first {
                let isBelowIt = lines[first..<own[index]].allSatisfy {
                    $0.rect.midY > sorted[index].rect.maxY
                }
                if isBelowIt { slots[index] = first }
            }
            start = end
        }
        return slots
    }
}

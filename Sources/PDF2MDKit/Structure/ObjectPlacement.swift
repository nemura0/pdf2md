import CoreGraphics
import Foundation

/// Something on a page that isn't running text: a table, a figure or an equation.
struct PageObject: Sendable, Equatable {
    var rect: CGRect
    var blocks: [Block]
    /// Text inside it is already part of the object, so it leaves the flow.
    var coversText: Bool
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
        let covering = objects.filter(\.coversText).map {
            $0.rect.insetBy(dx: -containmentTolerance, dy: -containmentTolerance)
        }
        guard !covering.isEmpty else { return lines }
        return lines.filter { line in
            let center = CGPoint(x: line.rect.midX, y: line.rect.midY)
            return !covering.contains { $0.contains(center) }
        }
    }

    /// Each object goes before the first line, in reading order, that is below its top and shares
    /// some of its width. That holds inside a column, where a later line can be higher on the
    /// page. An object with nothing below it goes last.
    static func segments(lines: [TextLine], objects: [PageObject]) -> [PageSegment] {
        let sorted = objects.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
        var pending = [Int: [PageObject]]()
        for object in sorted {
            let slot =
                lines.firstIndex { line in
                    line.rect.midY > object.rect.minY
                        && line.rect.minX < object.rect.maxX && line.rect.maxX > object.rect.minX
                } ?? lines.count
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
}

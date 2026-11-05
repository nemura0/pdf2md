import CoreGraphics
import CryptoKit
import Foundation

/// Finds drawings made of paths in the page's own content, like TikZ diagrams. They have no image
/// or form to find, so their labels used to land in the text as loose words between sentences.
public enum VectorFigures {
    /// Smaller marks are bullets. A real book draws them at 3.1 points.
    private static let minimumShapeSize = 4.0
    /// Shapes this close are one drawing: arrows stop short of their boxes.
    private static let reach = 6.0
    /// A box is a fill and an outline. One more thing makes it a drawing, and so does a rule
    /// inside it, since TikZ can draw a class box and its compartments as one path.
    private static let minimumShapes = 3
    private static let frameMargin = 2.0
    /// A captioned box or an arrow can belong to a drawing without touching any of its shapes. A
    /// real book's sit 6 to 13 points from the drawing.
    private static let partReach = 16.0
    private static let minimumWidth = 40.0
    private static let minimumHeight = 14.0
    /// Bars in a page's header and footer. The top of a real book's text starts at 7%.
    private static let marginBandShare = 0.06
    /// A line sticking out this far runs through the shapes, as with shaded code in a paragraph.
    private static let paragraphOverhang = 20.0
    /// Labels are short. Measured on a real book: at most 24 characters for a diagram's median
    /// line, and more than 100 for a paragraph.
    private static let longestMedianLabel = 40
    /// Shapes this wide or tall against the whole are a background or a frame.
    private static let spanningShare = 0.8
    private static let minimumNumberedLines = 2
    /// Labels above an array of cells, say, sit outside its shapes.
    private static let nearbyLabelGap = 8.0
    private static let nearbyLabelOverhang = 12.0
    private static let maximumNearbyLabelWords = 8
    /// A line beside a drawing has to be shorter, since text wrapped around it sits there too.
    private static let maximumBesideLabelWords = 4
    /// Labels don't end like this, and the last line of a sentence does.
    private static let sentenceEndings: Set<Character> = [".", ",", ";", ":", "?", "!"]
    private static let cropPadding = 2.0
    /// The middle of a letter, above the baseline, in font sizes. See `RuledTables`.
    private static let letterHeight = 0.7
    /// Positions in a digest are rounded to this, so a drawing's copy on another page matches.
    private static let digestPrecision = 10.0

    public static func find(
        shapes: [CGRect],
        rules: [RuleSegment],
        lines: [TextLine],
        tables: [CGRect],
        figures: [CGRect],
        pageSize: CGSize
    ) -> [CGRect] {
        let taken = (tables + figures).map { $0.insetBy(dx: -reach, dy: -reach) }
        let candidates = shapes.filter { shape in
            max(shape.width, shape.height) >= minimumShapeSize
                && !taken.contains { $0.contains(CGPoint(x: shape.midX, y: shape.midY)) }
        }
        let page = CGRect(origin: .zero, size: pageSize)
        let clusters = clusters(of: candidates)
        let bounds = { (cluster: [CGRect]) in
            cluster.dropFirst().reduce(cluster[0]) { $0.union($1) }
        }
        let isFigure = { (cluster: [CGRect]) in
            isDrawing(bounds(cluster), cluster: cluster, lines: lines, pageSize: pageSize)
        }
        let isLarge = { (cluster: [CGRect]) in
            cluster.count >= minimumShapes || hasCompartments(bounds(cluster), rules: rules)
        }
        let drawings = clusters.filter { isLarge($0) && isFigure($0) }
        // Each part looks at the lines once. Doing that per drawing took 11.5 s in a release build
        // on a page of 600 drawings, 3,000 parts and 500 lines, with the page's slot held.
        let parts = clusters.filter { !isLarge($0) && isFigure($0) }.map(bounds).map { part in
            DrawingPart(rect: part, holdsText: holdsText(part, lines: lines))
        }
        return
            drawings
            .compactMap { cluster -> CGRect? in
                let joined = addingParts(parts, to: bounds(cluster))
                // Off the page this is `CGRect.null`, with no size. Its infinities can't be
                // spooled, and the page's whole text would be lost with it.
                let area = addingNearbyLabels(to: joined, lines: lines).intersection(page)
                guard area.width >= minimumWidth, area.height >= minimumHeight else { return nil }
                return area.insetBy(dx: -cropPadding, dy: -cropPadding).intersection(page)
            }
            .sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
    }

    private struct DrawingPart {
        var rect: CGRect
        var holdsText: Bool
    }

    private static func holdsText(_ rect: CGRect, lines: [TextLine]) -> Bool {
        lines.contains { rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
    }

    /// Above or below a drawing, only a box with words in it joins: a lone line there can be a
    /// footnote's rule. Level with the drawing, a line or a curve is an arrow.
    private static func addingParts(_ parts: [DrawingPart], to bounds: CGRect) -> CGRect {
        let limit = bounds.insetBy(dx: -partReach, dy: -partReach)
        return parts.reduce(bounds) { area, part in
            let isLevel = part.rect.minY >= bounds.minY && part.rect.maxY <= bounds.maxY
            let isPart = limit.intersects(part.rect) && (part.holdsText || isLevel)
            return isPart ? area.union(part.rect) : area
        }
    }

    /// An identity for the crop's name. It holds the labels, because one book drew the same two
    /// boxes on three pages with different words, and they would have shared one picture.
    public static func digest(of rect: CGRect, shapes: [CGRect], words: [Word]) -> String {
        var hasher = SHA256()
        let add = { (value: CGFloat) in
            // A shape can be any size, and a plain conversion traps past Int64's range.
            var rounded = Int64(exactly: (Double(value) * digestPrecision).rounded()) ?? .max
            withUnsafeBytes(of: &rounded) { hasher.update(bufferPointer: $0) }
        }
        for shape in shapes where rect.contains(CGPoint(x: shape.midX, y: shape.midY)) {
            add(shape.minX - rect.minX)
            add(shape.minY - rect.minY)
            add(shape.width)
            add(shape.height)
        }
        for word in words where rect.contains(CGPoint(x: word.rect.midX, y: word.rect.midY)) {
            add(word.rect.minX - rect.minX)
            hasher.update(data: Data(word.text.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Telling drawings from page furniture

    private static func isDrawing(
        _ bounds: CGRect,
        cluster: [CGRect],
        lines: [TextLine],
        pageSize: CGSize
    ) -> Bool {
        let band = pageSize.height * marginBandShare
        guard bounds.midY >= band, bounds.midY <= pageSize.height - band,
            !FigureFilter.isPageSized(bounds, pageSize: pageSize),
            !isCrossedByText(bounds, lines: lines)
        else { return false }
        let inside = lines.filter { line in
            bounds.insetBy(dx: -cropPadding, dy: -cropPadding)
                .contains(CGPoint(x: line.rect.midX, y: line.rect.midY))
        }
        return !isCode(inside, cluster: cluster, bounds: bounds) && !isProse(inside)
    }

    private static func hasCompartments(_ bounds: CGRect, rules: [RuleSegment]) -> Bool {
        let inner = bounds.insetBy(dx: frameMargin, dy: frameMargin)
        return rules.contains { rule in
            let length = max(abs(rule.endX - rule.startX), abs(rule.endY - rule.startY))
            let middle = CGPoint(x: (rule.startX + rule.endX) / 2, y: (rule.startY + rule.endY) / 2)
            return length >= minimumShapeSize && inner.contains(middle)
        }
    }

    private static func isCrossedByText(_ bounds: CGRect, lines: [TextLine]) -> Bool {
        lines.contains { line in
            let letters = letterBox(of: line)
            return letters.minY < bounds.maxY && letters.maxY > bounds.minY
                && letters.minX < bounds.maxX && letters.maxX > bounds.minX
                && letters.width >= bounds.width
                && (bounds.minX - letters.minX > paragraphOverhang
                    || letters.maxX - bounds.maxX > paragraphOverhang)
        }
    }

    /// A listing's background or frame. A drawing labelled in monospace has smaller boxes.
    private static func isCode(_ inside: [TextLine], cluster: [CGRect], bounds: CGRect) -> Bool {
        if inside.filter({ $0.lineNumber != nil }).count >= minimumNumberedLines { return true }
        guard inside.filter(\.isMonospace).count * 2 >= inside.count, !inside.isEmpty else {
            return false
        }
        return cluster.allSatisfy { shape in
            shape.width >= bounds.width * spanningShare
                || shape.height >= bounds.height * spanningShare
        }
    }

    private static func isProse(_ inside: [TextLine]) -> Bool {
        let lengths = inside.map(\.text.count).sorted()
        guard !lengths.isEmpty else { return false }
        return lengths[lengths.count / 2] > longestMedianLabel
    }

    private static func addingNearbyLabels(to bounds: CGRect, lines: [TextLine]) -> CGRect {
        let limit = bounds.insetBy(dx: -nearbyLabelOverhang, dy: -nearbyLabelGap)
        return lines.reduce(bounds) { area, line in
            let letters = letterBox(of: line)
            let isLabel =
                line.words.count <= maximumNearbyLabelWords && letters.minX >= limit.minX
                && letters.maxX <= limit.maxX && letters.maxY >= limit.minY
                && letters.minY <= limit.maxY
            let joins = isLabel || isBesideLabel(line, letters: letters, limit: limit)
            return joins ? area.union(letters) : area
        }
    }

    /// A short line level with a drawing and reaching it from one side names something in it,
    /// however far it sticks out: `instancia1`, `frenar[vel>0]`. In monospace, it's more likely a
    /// listing set next to a shaded box of output.
    private static func isBesideLabel(_ line: TextLine, letters: CGRect, limit: CGRect) -> Bool {
        guard line.words.count <= maximumBesideLabelWords, !line.isMonospace,
            let last = line.text.last, !sentenceEndings.contains(last)
        else { return false }
        return letters.minY >= limit.minY && letters.maxY <= limit.maxY
            && letters.minX <= limit.maxX && letters.maxX >= limit.minX
    }

    /// Word boxes follow the font's bounding box and can reach the next line, so they can't say
    /// how near a line is. This is where its letters are.
    private static func letterBox(of line: TextLine) -> CGRect {
        CGRect(
            x: line.rect.minX,
            y: line.baseline - line.size * letterHeight,
            width: line.rect.width,
            height: line.size * letterHeight
        )
    }

    // MARK: Grouping

    /// Shapes within reach of each other, in groups. Sorted by position, so that only neighbours
    /// are compared: a page of a map can hold thousands of paths.
    private static func clusters(of shapes: [CGRect]) -> [[CGRect]] {
        let sorted = shapes.sorted { $0.minX < $1.minX }
        var parent = Array(sorted.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }
        for (first, shape) in sorted.enumerated() {
            for second in (first + 1)..<max(sorted.count, first + 1) {
                let other = sorted[second]
                if other.minX > shape.maxX + reach { break }
                if other.minY <= shape.maxY + reach, shape.minY <= other.maxY + reach {
                    parent[root(first)] = root(second)
                }
            }
        }
        var groups: [Int: [CGRect]] = [:]
        for (index, shape) in sorted.enumerated() {
            groups[root(index), default: []].append(shape)
        }
        return Array(groups.values)
    }
}

/// A drawing's words, each in about its place, so an LLM reading only the text can still tell which
/// box holds what. They cost no more than the loose lines they replace.
enum DiagramLabels {
    /// Two boxes side by side rarely share a baseline, and rows of a box are a full line apart.
    private static let sameRowShare = 0.6
    /// A huge page of tiny text shouldn't produce a line of a thousand spaces.
    private static let maximumColumn = 160
    /// Baselines this far apart, in font sizes, are separate rows of text.
    private static let separateRowShare = 0.9

    static func lines(from labels: [TextLine]) -> [String] {
        let lines = labels.flatMap(separatingStacked)
        guard let left = lines.map(\.rect.minX).min() else { return [] }
        let characters = lines.reduce(0) { $0 + $1.text.count }
        let width = lines.reduce(0.0) { $0 + Double($1.rect.width) }
        let cell = characters > 0 ? width / Double(characters) : 0
        return rows(of: lines).map { row in
            row.sorted { $0.rect.minX < $1.rect.minX }.reduce(into: "") { text, line in
                let place = cell > 0 ? (Double(line.rect.minX - left) / cell).rounded() : 0
                let column = min(Int(exactly: place) ?? maximumColumn, maximumColumn)
                let padding = text.isEmpty ? column : max(1, column - text.count)
                text += String(repeating: " ", count: padding) + TextNormalizer.normalize(line.text)
            }
        }
    }

    /// Words one above the other can't share a row. A taller mark at a height between two rows
    /// overlaps both, and `LineBuilder` joins them. That can only be undone here: in running text,
    /// the parts of a fraction look just the same, and they have to stay together.
    private static func separatingStacked(_ line: TextLine) -> [TextLine] {
        let isStacked = line.words.contains { upper in
            line.words.contains { lower in
                lower.baseline - upper.baseline >= max(upper.size, lower.size) * separateRowShare
                    && min(upper.rect.maxX, lower.rect.maxX) > max(upper.rect.minX, lower.rect.minX)
            }
        }
        guard isStacked else { return [line] }
        let rows = rows(of: line.words, baseline: \.baseline, size: \.size)
        return rows.map { TextLine(words: $0.sorted { $0.rect.minX < $1.rect.minX }) }
    }

    private static func rows(of lines: [TextLine]) -> [[TextLine]] {
        rows(of: lines, baseline: \.baseline, size: \.size)
    }

    private static func rows<Item>(
        of items: [Item],
        baseline: KeyPath<Item, Double>,
        size: KeyPath<Item, Double>
    ) -> [[Item]] {
        var rows: [[Item]] = []
        for item in items.sorted(by: { $0[keyPath: baseline] < $1[keyPath: baseline] }) {
            if let first = rows.last?.first,
                item[keyPath: baseline] - first[keyPath: baseline]
                    <= first[keyPath: size] * sameRowShare
            {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows
    }
}

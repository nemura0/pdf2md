import CoreGraphics
import Foundation

/// A display equation over several lines: stacked fractions, matrices, limits under a sum. Its
/// linear form loses structure, so it travels with a cropped image (ADR-0005).
public struct StackedEquation: Sendable, Equatable {
    public var lines: [TextLine]
    public var rect: CGRect
    public var linearLatex: String
}

public enum StackedEquations {
    /// Text lines sit a full line apart. Parts of one formula overlap or nearly touch.
    private static let stackedGapRatio = 1.5
    private static let rulePadding = 2.0

    public static func find(in lines: [TextLine], rules: [RuleSegment]) -> [StackedEquation] {
        let ordered = lines.sorted { $0.baseline < $1.baseline }
        var clusters: [[TextLine]] = []
        var current: [TextLine] = []
        for line in ordered {
            guard isMathLine(line) else {
                flush(&current, into: &clusters)
                continue
            }
            if let last = current.last, !belongTogether(last, line, rules: rules) {
                flush(&current, into: &clusters)
            }
            current.append(line)
        }
        flush(&current, into: &clusters)
        return clusters.map(makeEquation)
    }

    private static func flush(_ current: inout [TextLine], into clusters: inout [[TextLine]]) {
        if current.count > 1 { clusters.append(current) }
        current = []
    }

    private static func isMathLine(_ line: TextLine) -> Bool {
        line.words.contains(where: MathSpans.isMath) && MathSpans.displayLatexAllowingOne(line)
    }

    private static func belongTogether(
        _ upper: TextLine,
        _ lower: TextLine,
        rules: [RuleSegment]
    ) -> Bool {
        let overlaps =
            upper.rect.minX < lower.rect.maxX + upper.size * 2
            && lower.rect.minX < upper.rect.maxX + upper.size * 2
        guard overlaps else { return false }
        let gap = lower.baseline - upper.baseline
        if gap < upper.size * stackedGapRatio { return true }
        return rules.contains { rule in
            rule.isHorizontal
                && rule.startY > upper.baseline - rulePadding
                && rule.startY < lower.rect.minY + rulePadding
                && min(rule.startX, rule.endX) < max(upper.rect.maxX, lower.rect.maxX)
                && max(rule.startX, rule.endX) > min(upper.rect.minX, lower.rect.minX)
        }
    }

    private static func makeEquation(_ lines: [TextLine]) -> StackedEquation {
        let rect = lines.dropFirst().reduce(lines[0].rect) { $0.union($1.rect) }
        return StackedEquation(lines: lines, rect: rect, linearLatex: linearForm(lines))
    }

    /// The line with the leftmost start carries the left side (`R =`). The rest read top to
    /// bottom, separated by `/`, the closest linear reading of a fraction.
    private static func linearForm(_ lines: [TextLine]) -> String {
        let latex = lines.map { MathSpans.latex($0.words, baseline: $0.baseline, size: $0.size) }
        guard let leftIndex = lines.indices.min(by: { lines[$0].rect.minX < lines[$1].rect.minX })
        else { return "" }
        let isLeftSide =
            lines[leftIndex].rect.maxX
            <= lines
            .enumerated()
            .filter { $0.offset != leftIndex }
            .map(\.element.rect.minX)
            .min() ?? 0
        guard isLeftSide else { return latex.joined(separator: " / ") }
        let others = latex.enumerated().filter { $0.offset != leftIndex }.map(\.element)
        return latex[leftIndex] + " " + others.joined(separator: " / ")
    }
}

extension MathSpans {
    /// Part of a stack can be one token, such as a lone denominator.
    static func displayLatexAllowingOne(_ line: TextLine) -> Bool {
        line.words.allSatisfy { isMath($0) || $0.text.allSatisfy(connectorCharacters.contains) }
    }

    private static var connectorCharacters: Set<Character> {
        Set("=+-−*/<>()[]{}|^,:0123456789.'")
    }
}

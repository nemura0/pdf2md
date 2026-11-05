import CoreGraphics
import Foundation

/// Finds running headers, footers and page numbers: margin lines that repeat once their digits
/// are normalized.
public enum MarginFilter {
    /// The share of the page height at the top and at the bottom that counts as margin.
    static let marginShare = 0.1

    /// The comparison key: lowercase, digits and roman numerals as `#`, single spaces. A page
    /// number at either end is dropped, because books print it on the outer edge, so odd and even
    /// pages would otherwise count as two different headers.
    public static func key(for text: String) -> String {
        let tokens = text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { token in isRoman(token) ? "#" : collapsingDigits(token) }
        var core = tokens[...]
        while core.first == "#" { core = core.dropFirst() }
        while core.last == "#" { core = core.dropLast() }
        return core.isEmpty ? (tokens.isEmpty ? "" : "#") : core.joined(separator: " ")
    }

    public static func isInMargin(_ rect: CGRect, pageHeight: Double) -> Bool {
        rect.midY < pageHeight * marginShare || rect.midY > pageHeight * (1 - marginShare)
    }

    private static func isRoman(_ token: Substring) -> Bool {
        token.wholeMatch(of: /m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})/) != nil
    }

    private static func collapsingDigits(_ token: Substring) -> String {
        var output = ""
        var wasDigit = false
        for character in token {
            if character.isNumber {
                if !wasDigit { output.append("#") }
                wasDigit = true
            } else {
                output.append(character)
                wasDigit = false
            }
        }
        return output
    }
}

/// Counts margin keys across pages. A key is repeated if it reaches `max(3 pages, 30%)`, or, on
/// portrait pages, appears on three pages close together, which catches per-chapter headers that
/// never reach 30% of a long book. Slides are exempt from that rule, because builds repeat
/// content on consecutive slides.
public struct MarginTracker: Sendable {
    /// At 30% alone, a two-page PDF would lose every line it has in common.
    private static let minimumPages = 3
    private static let repeatShare = 0.3
    private static let localRunLength = 3
    /// Odd and even pages often have different headers, so a run may skip one page.
    private static let localRunMaximumGap = 2
    private static let pruneInterval = 256

    private struct Entry: Sendable {
        var count = 0
        var run = 0
        var lastPage = -1
        var isLocalRepeat = false
    }

    private let pageCount: Int
    private let threshold: Int
    private var entries: [String: Entry] = [:]
    private var pagesSeen = 0

    public init(pageCount: Int) {
        self.pageCount = pageCount
        self.threshold = Self.threshold(forPageCount: pageCount)
    }

    static func threshold(forPageCount pageCount: Int) -> Int {
        max(minimumPages, Int((Double(pageCount) * repeatShare).rounded(.up)))
    }

    public mutating func add(page: Int, keys: [String], isLandscape: Bool) {
        for key in Set(keys) where !key.isEmpty {
            var entry = entries[key] ?? Entry()
            entry.count += 1
            entry.run = page - entry.lastPage <= Self.localRunMaximumGap ? entry.run + 1 : 1
            entry.lastPage = page
            if entry.run >= Self.localRunLength, !isLandscape, pageCount >= Self.minimumPages {
                entry.isLocalRepeat = true
            }
            entries[key] = entry
        }
        pagesSeen += 1
        if pagesSeen.isMultiple(of: Self.pruneInterval) { prune() }
    }

    public func repeatedKeys() -> Set<String> {
        Set(
            entries.compactMap { key, entry in
                entry.count >= threshold || entry.isLocalRepeat ? key : nil
            }
        )
    }

    /// For tests: the number of keys still being counted.
    var trackedKeyCount: Int { entries.count }

    /// Drops keys that can't reach the threshold any more, so counters stay bounded.
    private mutating func prune() {
        let remaining = pageCount - pagesSeen
        entries = entries.filter { _, entry in
            entry.isLocalRepeat || entry.count + remaining >= threshold
                || pagesSeen - entry.lastPage <= Self.localRunMaximumGap
        }
    }
}

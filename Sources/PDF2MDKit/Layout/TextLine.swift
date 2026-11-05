import CoreGraphics

/// Words on one baseline, in x order. Sub and superscripts keep their own baselines, and the
/// line's own values come from the characters that are most common.
public struct TextLine: Sendable, Equatable {
    /// A line counts as bold or monospace only if nearly all of it is.
    private static let styleShare = 0.9
    /// Line numbers are set no larger than the code beside them, usually much smaller. A word
    /// space is a third of a font size, so a gutter is at least this much wider.
    private static let minimumGutterGap = 0.5
    private static let maximumLineNumberDigits = 5

    public let words: [Word]
    /// A listing's line number, kept apart from the code it numbers. See `isLineNumber`.
    public let lineNumber: Word?
    /// The words without the line number, which is all there is to judge the line's style by.
    public let contentWords: [Word]
    public let rect: CGRect
    public let baseline: Double
    public let size: Double
    public let isBold: Bool
    public let isMonospace: Bool
    public let text: String

    public init(words: [Word]) {
        self.words = words
        let hasLineNumber = words.count >= 2 && Self.isLineNumber(words[0], before: words[1])
        self.lineNumber = hasLineNumber ? words[0] : nil
        self.contentWords = hasLineNumber ? Array(words.dropFirst()) : words
        self.rect = words.dropFirst().reduce(words.first?.rect ?? .zero) { $0.union($1.rect) }
        self.text = words.enumerated().reduce(into: "") { text, item in
            if item.offset > 0, !item.element.isGlued { text += " " }
            text += item.element.text
        }

        var charsBySize: [Double: Int] = [:]
        var charsByBaseline: [Double: Int] = [:]
        var boldChars = 0
        var monoChars = 0
        var totalChars = 0
        for word in contentWords {
            let count = word.text.count
            charsBySize[word.size, default: 0] += count
            charsByBaseline[word.baseline, default: 0] += count
            totalChars += count
            if word.font.isBold { boldChars += count }
            if word.font.isMonospace { monoChars += count }
        }
        self.size = Self.mostCommon(charsBySize)
        self.baseline = Self.mostCommon(charsByBaseline)
        let threshold = Double(totalChars) * Self.styleShare
        self.isBold = totalChars > 0 && Double(boldChars) >= threshold
        self.isMonospace = totalChars > 0 && Double(monoChars) >= threshold
    }

    /// True for a listing's line number: digits in a text font and no larger than the code, set
    /// apart from it. LaTeX's `listings` sets them small, and it's the gap that keeps a footnote
    /// marker on a URL out of this.
    static func isLineNumber(_ word: Word, before next: Word) -> Bool {
        isPlainNumber(word) && next.font.isMonospace && !next.isGlued
            && word.size <= next.size
            && next.rect.minX - word.rect.maxX >= next.size * minimumGutterGap
    }

    static func isPlainNumber(_ word: Word) -> Bool {
        !word.font.isMonospace && word.text.count <= maximumLineNumberDigits
            && word.text.allSatisfy(\.isASCIINumber)
    }

    /// Ties go to the larger key, so the result doesn't depend on dictionary order.
    private static func mostCommon(_ counts: [Double: Int]) -> Double {
        counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
    }
}

extension Character {
    fileprivate var isASCIINumber: Bool { isASCII && isNumber }
}

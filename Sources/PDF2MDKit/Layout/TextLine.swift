import CoreGraphics

/// Words on one baseline, in x order. Sub and superscripts keep their own baselines, and the
/// line's own values come from the characters that are most common.
public struct TextLine: Sendable, Equatable {
    /// A line counts as bold or monospace only if nearly all of it is.
    private static let styleShare = 0.9

    public let words: [Word]
    public let rect: CGRect
    public let baseline: Double
    public let size: Double
    public let isBold: Bool
    public let isMonospace: Bool
    public let text: String

    public init(words: [Word]) {
        self.words = words
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
        for word in words {
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

    /// Ties go to the larger key, so the result doesn't depend on dictionary order.
    private static func mostCommon(_ counts: [Double: Int]) -> Double {
        counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key ?? 0
    }
}

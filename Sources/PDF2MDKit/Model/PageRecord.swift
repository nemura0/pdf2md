import CoreGraphics
import Foundation

/// Font facts for a word. Names come from the content stream, not `NSFont` (ADR-0003).
public struct FontStyle: Codable, Sendable, Hashable {
    public var name: String
    public var isBold: Bool
    public var isItalic: Bool
    public var isMonospace: Bool

    public init(name: String, isBold: Bool, isItalic: Bool, isMonospace: Bool) {
        self.name = name
        self.isBold = isBold
        self.isItalic = isItalic
        self.isMonospace = isMonospace
    }
}

/// A word in display space: points, origin at the top left of the rotated page, y down.
public struct Word: Sendable, Equatable {
    public var text: String
    public var rect: CGRect
    public var baseline: Double
    public var size: Double
    public var font: FontStyle
    /// No space before this word: it was split from the previous one at a font boundary.
    public var isGlued: Bool

    public init(
        text: String,
        rect: CGRect,
        baseline: Double,
        size: Double,
        font: FontStyle,
        isGlued: Bool = false
    ) {
        self.text = text
        self.rect = rect
        self.baseline = baseline
        self.size = size
        self.font = font
        self.isGlued = isGlued
    }
}

/// A straight segment from the content stream: table rules, fraction bars.
public struct RuleSegment: Codable, Sendable, Equatable {
    public var startX: Double
    public var startY: Double
    public var endX: Double
    public var endY: Double

    public init(startX: Double, startY: Double, endX: Double, endY: Double) {
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
    }

    public var isHorizontal: Bool { abs(endY - startY) < 1 && abs(endX - startX) >= 1 }
    public var isVertical: Bool { abs(endX - startX) < 1 && abs(endY - startY) >= 1 }
}

/// A figure found on a page. `cropFile` is set when the worker saved a crop in the spool.
public struct FigureCandidate: Codable, Sendable, Equatable {
    public var digest: String
    public var rect: CGRect
    public var cropFile: String?

    public init(digest: String, rect: CGRect, cropFile: String? = nil) {
        self.digest = digest
        self.rect = rect
        self.cropFile = cropFile
    }
}

/// A table found on a page, with its text already taken out of the flow by rect.
public struct TableRegion: Codable, Sendable, Equatable {
    public var rect: CGRect
    public var rows: [[String]]

    public init(rect: CGRect, rows: [[String]]) {
        self.rect = rect
        self.rows = rows
    }
}

/// An equation that couldn't be rebuilt confidently, with a crop to keep next to it.
public struct EquationCrop: Codable, Sendable, Equatable {
    public var rect: CGRect
    public var cropFile: String

    public init(rect: CGRect, cropFile: String) {
        self.rect = rect
        self.cropFile = cropFile
    }
}

/// Everything the emit stage needs about one page. It never opens the PDF (ADR-0006).
public struct PageRecord: Sendable, Equatable {
    public var index: Int
    public var width: Double
    public var height: Double
    public var words: [Word]
    public var figures: [FigureCandidate]
    public var tables: [TableRegion]
    public var equations: [EquationCrop]
    public var rules: [RuleSegment]
    public var isOCR: Bool
    public var matchedWords: Int
    public var unmatchedWords: Int
    public var didFail: Bool

    public init(
        index: Int,
        width: Double,
        height: Double,
        words: [Word] = [],
        figures: [FigureCandidate] = [],
        tables: [TableRegion] = [],
        equations: [EquationCrop] = [],
        rules: [RuleSegment] = [],
        isOCR: Bool = false,
        matchedWords: Int = 0,
        unmatchedWords: Int = 0,
        didFail: Bool = false
    ) {
        self.index = index
        self.width = width
        self.height = height
        self.words = words
        self.figures = figures
        self.tables = tables
        self.equations = equations
        self.rules = rules
        self.isOCR = isOCR
        self.matchedWords = matchedWords
        self.unmatchedWords = unmatchedWords
        self.didFail = didFail
    }

    public var size: CGSize { CGSize(width: width, height: height) }
}

// The spool holds one record per page, so words use a font table and short keys instead of
// the synthesized form, which repeats every font name on every word.
extension PageRecord: Codable {
    private struct CompactWord: Codable {
        var t: String
        var r: [Double]
        var b: Double
        var s: Double
        var f: Int
        var g: Bool?
    }

    private enum CodingKeys: String, CodingKey {
        case index, width, height, fonts, words, figures, tables, equations, rules, isOCR
        case matchedWords, unmatchedWords, didFail
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var fontIndex: [FontStyle: Int] = [:]
        var fonts: [FontStyle] = []
        let compact = words.map { word -> CompactWord in
            let index =
                fontIndex[word.font]
                ?? {
                    fonts.append(word.font)
                    fontIndex[word.font] = fonts.count - 1
                    return fonts.count - 1
                }()
            return CompactWord(
                t: word.text,
                r: [word.rect.minX, word.rect.minY, word.rect.width, word.rect.height],
                b: word.baseline,
                s: word.size,
                f: index,
                g: word.isGlued ? true : nil
            )
        }
        try container.encode(index, forKey: .index)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fonts, forKey: .fonts)
        try container.encode(compact, forKey: .words)
        try container.encode(figures, forKey: .figures)
        try container.encode(tables, forKey: .tables)
        try container.encode(equations, forKey: .equations)
        try container.encode(rules, forKey: .rules)
        try container.encode(isOCR, forKey: .isOCR)
        try container.encode(matchedWords, forKey: .matchedWords)
        try container.encode(unmatchedWords, forKey: .unmatchedWords)
        try container.encode(didFail, forKey: .didFail)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fonts = try container.decode([FontStyle].self, forKey: .fonts)
        let compact = try container.decode([CompactWord].self, forKey: .words)
        self.index = try container.decode(Int.self, forKey: .index)
        self.width = try container.decode(Double.self, forKey: .width)
        self.height = try container.decode(Double.self, forKey: .height)
        self.words = compact.map { word in
            Word(
                text: word.t,
                rect: CGRect(x: word.r[0], y: word.r[1], width: word.r[2], height: word.r[3]),
                baseline: word.b,
                size: word.s,
                font: fonts[word.f],
                isGlued: word.g ?? false
            )
        }
        self.figures = try container.decode([FigureCandidate].self, forKey: .figures)
        self.tables = try container.decode([TableRegion].self, forKey: .tables)
        self.equations = try container.decode([EquationCrop].self, forKey: .equations)
        self.rules = try container.decode([RuleSegment].self, forKey: .rules)
        self.isOCR = try container.decode(Bool.self, forKey: .isOCR)
        self.matchedWords = try container.decode(Int.self, forKey: .matchedWords)
        self.unmatchedWords = try container.decode(Int.self, forKey: .unmatchedWords)
        self.didFail = try container.decode(Bool.self, forKey: .didFail)
    }
}

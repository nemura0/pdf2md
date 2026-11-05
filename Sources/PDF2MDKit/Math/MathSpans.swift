import Foundation
import Synchronization

/// Finds math in a line and renders it. Detection is by font and by character, not by meaning, so
/// `a = b` in a text font stays text.
public enum MathSpans {
    private static let mathFontMarkers = [
        "cmmi", "cmsy", "cmex", "cmbsy", "msbm", "msam", "eufm", "eusm", "rsfs", "lmmath",
        "mtmi", "mtsy", "txmi", "txsy", "pxmi", "pxsy", "cambriamath", "symbolmt",
        "stixintegrals", "stixsize", "stixvariants", "stixnonuni",
    ]
    /// STIX is also a text family, as in matplotlib's labels and many journals, so only its short
    /// italic words are variables.
    private static let stixTextMarker = "stix"
    private static let maximumStixVariableLength = 2
    private static let mathWordInFontName = "math"
    /// `Mathilde` and friends: `math` must start a new word in the font's name.
    private static let mathWordEnders = Set("-_ ")

    /// A script is clearly smaller than its line and sits off its baseline.
    private static let scriptSizeRatio = 0.85
    private static let scriptOffsetRatio = 0.12
    /// Operators and numbers that belong to a formula, but aren't math by themselves.
    private static let connectors = Set("=+-−*/<>()[]{}|^,:0123456789.'")
    private static let maximumConnectorLength = 8
    private static let minimumDisplayTokens = 2

    public static func isMathFont(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if mathFontMarkers.contains(where: lowered.contains) { return true }
        guard let range = lowered.range(of: mathWordInFontName) else { return false }
        let isWordStart =
            range.lowerBound == lowered.startIndex
            || mathWordEnders.contains(lowered[lowered.index(before: range.lowerBound)])
            || lowered[lowered.index(before: range.lowerBound)].isLowercase
        let next = range.upperBound < lowered.endIndex ? lowered[range.upperBound] : "-"
        return isWordStart && !next.isLetter
    }

    public static func isMath(_ word: Word) -> Bool {
        let family = family(ofFont: word.font.name)
        if family.isMath { return true }
        if family.isStix, word.font.isItalic, word.text.count <= maximumStixVariableLength {
            return true
        }
        return word.text.contains(where: isMathCharacter)
    }

    private struct FontFamily {
        var isMath: Bool
        var isStix: Bool
    }

    /// Every word of the document passes here, and a document has only a handful of fonts.
    /// Matching names each time took a 700-page book from 9.2 to 13.7 s.
    private static let families = Mutex<[String: FontFamily]>([:])

    private static func family(ofFont name: String) -> FontFamily {
        families.withLock { known in
            if let family = known[name] { return family }
            let family = FontFamily(
                isMath: isMathFont(name),
                isStix: name.lowercased().contains(stixTextMarker)
            )
            known[name] = family
            return family
        }
    }

    static func isMathCharacter(_ character: Character) -> Bool {
        // Plain ASCII is never math by itself, and it's nearly all a document has.
        guard !character.isASCII, let scalar = character.unicodeScalars.first else { return false }
        if MathMapper.plainCharacter(for: scalar) != nil { return true }
        let isEscapable = "×·°…′″¬±÷".contains(character)
        return MathMapper.hasCommand(character) && !isEscapable
    }

    private static func isConnector(_ word: Word) -> Bool {
        word.text.count <= maximumConnectorLength && word.text.allSatisfy(connectors.contains)
    }

    /// Markdown for a line that contains math, or nil if it has none, so the caller's plain path
    /// stays untouched. Text around the math comes back already escaped.
    public static func render(_ words: [Word], baseline: Double, size: Double) -> String? {
        let marks = spanMarks(words)
        guard marks.contains(true) else { return nil }
        var output = ""
        var index = 0
        while index < words.count {
            let isFirst = output.isEmpty
            if marks[index] {
                var end = index
                while end + 1 < words.count, marks[end + 1] { end += 1 }
                let latex = latex(Array(words[index...end]), baseline: baseline, size: size)
                if !isFirst, !words[index].isGlued { output += " " }
                output += "$" + latex + "$"
                index = end + 1
            } else {
                if !isFirst, !words[index].isGlued { output += " " }
                output += InlineRenderer.escape(TextNormalizer.normalize(words[index].text))
                index += 1
            }
        }
        return output
    }

    /// The formulas in a page's blocks, for the log.
    static func count(in blocks: [Block]) -> Int {
        blocks.reduce(0) { total, block in
            switch block {
            case .displayMath: total + 1
            case .paragraph(let text), .heading(_, let text): total + inlineCount(in: text)
            case .list(let items):
                total + items.reduce(0) { $0 + inlineCount(in: $1.text) }
            case .table(let rows):
                total + rows.joined().reduce(0) { $0 + inlineCount(in: $1) }
            case .code, .figure: total
            }
        }
    }

    /// A literal dollar sign in text is escaped, so bare ones come in pairs.
    private static func inlineCount(in text: String) -> Int {
        var bare = 0
        var isEscaped = false
        for character in text {
            if character == "$", !isEscaped { bare += 1 }
            isEscaped = character == "\\" && !isEscaped
        }
        return bare / 2
    }

    /// LaTeX if the whole line is a formula: enough tokens, and no word of plain text.
    public static func displayLatex(_ line: TextLine) -> String? {
        let marks = spanMarks(line.words)
        guard !marks.isEmpty, marks.allSatisfy({ $0 }), line.words.count >= minimumDisplayTokens
        else { return nil }
        return latex(line.words, baseline: line.baseline, size: line.size)
    }

    /// Which words are in a formula: math words, and connectors between or right after them. A
    /// sentence's final comma or period stays out.
    private static func spanMarks(_ words: [Word]) -> [Bool] {
        var marks = words.map(isMath)
        guard marks.contains(true) else { return marks }
        var index = 0
        while index < words.count {
            guard !marks[index], isConnector(words[index]) else {
                index += 1
                continue
            }
            var end = index
            while end + 1 < words.count, !marks[end + 1], isConnector(words[end + 1]) { end += 1 }
            let hasMathBefore = index > 0 && marks[index - 1]
            let hasMathAfter = end + 1 < words.count && marks[end + 1]
            if hasMathBefore, hasMathAfter {
                for inner in index...end { marks[inner] = true }
            } else if hasMathBefore || hasMathAfter {
                for inner in index...end where !isSentencePunctuation(words[inner]) {
                    marks[inner] = true
                }
            }
            index = end + 1
        }
        return marks
    }

    private static func isSentencePunctuation(_ word: Word) -> Bool {
        word.text.allSatisfy { ",.:".contains($0) }
    }

    /// Builds LaTeX for words in a span, rebuilding sub and superscripts from size and baseline.
    public static func latex(_ words: [Word], baseline: Double, size: Double) -> String {
        var output = ""
        var index = 0
        while index < words.count {
            let word = words[index]
            let kind = scriptKind(word, baseline: baseline, size: size)
            guard let kind else {
                if !output.isEmpty, !word.isGlued { output += " " }
                output = appending(MathMapper.latex(for: word.text), to: output)
                index += 1
                continue
            }
            var content = MathMapper.latex(for: word.text)
            var end = index
            while end + 1 < words.count,
                scriptKind(words[end + 1], baseline: baseline, size: size) == kind
            {
                end += 1
                content += MathMapper.latex(for: words[end].text)
            }
            output += kind + (content.count == 1 ? content : "{\(content)}")
            index = end + 1
        }
        return output
    }

    private static func appending(_ piece: String, to output: String) -> String {
        let needsSpace =
            MathMapper.endsInCommand(output) && piece.first?.isLetter == true
        return output + (needsSpace ? " " : "") + piece
    }

    private static func scriptKind(_ word: Word, baseline: Double, size: Double) -> String? {
        guard word.isGlued, size > 0, word.size <= size * scriptSizeRatio else { return nil }
        let offset = word.baseline - baseline
        if offset < -size * scriptOffsetRatio { return "^" }
        if offset > size * scriptOffsetRatio { return "_" }
        return nil
    }
}

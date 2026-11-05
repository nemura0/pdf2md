import CoreGraphics
import Foundation

/// Turns OCR lines into the same `Word` model as a text layer, so one layout path serves both.
public enum RecognizedWords {
    /// Vision's line heights are too noisy to rank. Measured on one scanned page: body lines from
    /// 9.9 to 11.6 pt, and a 13 pt heading at 14.9 while another measured 13.2. Width per
    /// character separates them: 4.8 to 5.2 for body, 7.1 and 8.5 for headings.
    private static let emPerCharacterWidth = 2.0
    /// Coarse, because one style must come out as one size for heading ranks to work.
    private static let sizeStep = 2.0
    /// Lines this close to the page's typical size are that size, with noise.
    private static let sameStyleRatio = 1.2
    /// A short line's width says little, since `ill` and `MMM` differ by a factor of three.
    private static let minimumMeasuredCharacters = 12
    private static let baselineShareOfHeight = 0.8
    private static let nonHeadingEndings = Set(".,;:{}")
    private static let minimumHeadingLetterShare = 0.5
    private static let ocrFont = FontStyle(
        name: "",
        isBold: false,
        isItalic: false,
        isMonospace: false
    )

    private struct Measured {
        let rect: CGRect
        let tokens: [String]
        let characters: Int

        var estimatedSize: Double {
            rect.width / Double(characters) * emPerCharacterWidth
        }
    }

    public static func words(from lines: [RecognizedLine], pageSize: CGSize) -> [Word] {
        let measured = lines.compactMap { measure($0, pageSize: pageSize) }
        let typical = typicalSize(of: measured)
        return measured.flatMap { line in
            words(in: line, size: size(of: line, typical: typical))
        }
    }

    private static func measure(_ line: RecognizedLine, pageSize: CGSize) -> Measured? {
        let rect = line.rect.denormalized(to: pageSize)
        let tokens = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        let characters = tokens.reduce(0) { $0 + $1.count } + max(tokens.count - 1, 0)
        guard characters > 0, rect.width > 0, rect.height > 0 else { return nil }
        return Measured(rect: rect, tokens: tokens, characters: characters)
    }

    /// The character-weighted median over lines long enough to measure.
    private static func typicalSize(of lines: [Measured]) -> Double {
        let long = lines.filter { $0.characters >= minimumMeasuredCharacters }
        let sample = (long.isEmpty ? lines : long).sorted { $0.estimatedSize < $1.estimatedSize }
        let middle = sample.reduce(0) { $0 + $1.characters } / 2
        var seen = 0
        for line in sample {
            seen += line.characters
            if seen > middle { return line.estimatedSize }
        }
        return sample.last?.estimatedSize ?? 0
    }

    private static func size(of line: Measured, typical: Double) -> Double {
        let estimate = line.estimatedSize
        let isLarger = estimate > typical * sameStyleRatio && canBeHeading(line)
        let isSmaller = estimate < typical / sameStyleRatio
        let isSameStyle =
            !isLarger && (!isSmaller || line.characters < minimumMeasuredCharacters)
        let size = isSameStyle ? typical : estimate
        return max((size / sizeStep).rounded() * sizeStep, sizeStep)
    }

    /// Only size can mark a heading here, and these measure large for other reasons: the tail of
    /// a sentence (`hand.`), code in a wider font, and math (`R= 2n-1`).
    private static func canBeHeading(_ line: Measured) -> Bool {
        let text = line.tokens.joined()
        guard let last = text.last, !nonHeadingEndings.contains(last) else { return false }
        let letters = text.filter(\.isLetter).count
        return Double(letters) >= Double(text.count) * minimumHeadingLetterShare
    }

    private static func words(in line: Measured, size: Double) -> [Word] {
        let unit = line.rect.width / Double(line.characters)
        var x = Double(line.rect.minX)
        return line.tokens.map { token in
            let width = Double(token.count) * unit
            defer { x += width + unit }
            return Word(
                text: token,
                rect: CGRect(x: x, y: line.rect.minY, width: width, height: line.rect.height),
                baseline: line.rect.minY + line.rect.height * baselineShareOfHeight,
                size: size,
                font: ocrFont
            )
        }
    }
}

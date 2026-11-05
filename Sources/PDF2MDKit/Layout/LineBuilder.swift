import CoreGraphics

/// Builds lines from word geometry, because `page.string` merges columns that share a baseline
/// (measured: ADR-0003).
public enum LineBuilder {
    /// Share of the shorter word's height two words must overlap to sit on one line. Stacked
    /// fractions overlap by about a third, so this keeps them apart.
    private static let minimumOverlap = 0.4
    /// A gap this wide (in font sizes) isn't a word space. Justified text reaches about one.
    private static let columnGap = 1.6
    /// Words closer than this with the same text are one word drawn twice for fake bold.
    private static let duplicateTolerance = 1.5
    /// Copies drawn on top of each other come out of PDFKit as one word that's twice as long and
    /// no wider. Measured on a real book: 0.245 font sizes per letter, where about 0.5 is normal.
    private static let overprintWidthShare = 0.35
    private static let minimumOverprintLength = 6

    public static func lines(from words: [Word]) -> [TextLine] {
        clusters(of: words.map(collapsingOverprint)).flatMap { cluster -> [TextLine] in
            let sorted = cluster.sorted { $0.rect.minX < $1.rect.minX }
            return segments(of: removingDuplicates(sorted)).map(TextLine.init(words:))
        }
    }

    private static func collapsingOverprint(_ word: Word) -> Word {
        let count = word.text.count
        guard count >= minimumOverprintLength, count.isMultiple(of: 2),
            word.rect.width < Double(count) * word.size * overprintWidthShare
        else { return word }
        let half = String(word.text.prefix(count / 2))
        guard word.text.hasSuffix(half) else { return word }
        var single = word
        single.text = half
        return single
    }

    /// Groups words into vertical bands. The band follows the largest word seen so far, so a
    /// superscript met first doesn't narrow it.
    private static func clusters(of words: [Word]) -> [[Word]] {
        let sorted = words.sorted { $0.rect.midY < $1.rect.midY }
        var clusters: [[Word]] = []
        var band = CGRect.null
        for word in sorted {
            if !clusters.isEmpty, overlapShare(word.rect, band) >= minimumOverlap {
                clusters[clusters.count - 1].append(word)
                if word.rect.height > band.height { band = word.rect }
            } else {
                clusters.append([word])
                band = word.rect
            }
        }
        return clusters
    }

    private static func overlapShare(_ first: CGRect, _ second: CGRect) -> Double {
        let overlap = min(first.maxY, second.maxY) - max(first.minY, second.minY)
        let shorter = min(first.height, second.height)
        return shorter > 0 ? overlap / shorter : 0
    }

    private static func removingDuplicates(_ words: [Word]) -> [Word] {
        var kept: [Word] = []
        for word in words {
            if let last = kept.last, last.text == word.text,
                abs(last.rect.minX - word.rect.minX) < duplicateTolerance
            {
                continue
            }
            kept.append(word)
        }
        return kept
    }

    /// Splits at column gaps. Monospace words never split, since wide gaps there are alignment,
    /// and neither does a line number from its code, however deeply that code is indented.
    private static func segments(of words: [Word]) -> [[Word]] {
        var segments: [[Word]] = []
        for word in words {
            guard let previous = segments.last?.last else {
                segments.append([word])
                continue
            }
            let gap = word.rect.minX - previous.rect.maxX
            let isAlignment =
                word.font.isMonospace
                && (previous.font.isMonospace || TextLine.isLineNumber(previous, before: word))
            if gap > columnGap * max(word.size, previous.size), !isAlignment {
                segments.append([word])
            } else {
                segments[segments.count - 1].append(word)
            }
        }
        return segments
    }
}

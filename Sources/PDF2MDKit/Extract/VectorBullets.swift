import CoreGraphics

/// Some LaTeX classes draw list bullets as small filled squares, so the text layer has no marker
/// and a list reads as loose lines. This puts the marker back as a word, which the list stage then
/// treats like any other bullet.
enum VectorBullets {
    static let sideRange = 1.5...8.0
    private static let maximumAspect = 1.4
    /// A bullet is smaller than the text beside it, and close to it.
    private static let maximumShareOfSize = 0.6
    private static let maximumGapInSizes = 3.0
    /// Where a mark can sit on a line, in font sizes around the baseline.
    private static let reachAboveBaseline = 0.9
    private static let reachBelowBaseline = 0.2

    static func isMarkShaped(_ rect: CGRect) -> Bool {
        let longer = max(rect.width, rect.height)
        let shorter = min(rect.width, rect.height)
        return sideRange.contains(longer) && shorter > 0 && longer / shorter <= maximumAspect
    }

    static func words(marks: [CGRect], text: [Word]) -> [Word] {
        marks.compactMap { mark in
            let row = text.filter { word in
                mark.midY >= word.baseline - word.size * reachAboveBaseline
                    && mark.midY <= word.baseline + word.size * reachBelowBaseline
            }
            guard let first = row.min(by: { $0.rect.minX < $1.rect.minX }),
                row.allSatisfy({ $0.rect.minX >= mark.maxX }),
                first.rect.minX - mark.maxX <= first.size * maximumGapInSizes,
                mark.height <= first.size * maximumShareOfSize
            else { return nil }
            return Word(
                text: "•",
                rect: mark,
                baseline: first.baseline,
                size: first.size,
                font: first.font
            )
        }
    }
}

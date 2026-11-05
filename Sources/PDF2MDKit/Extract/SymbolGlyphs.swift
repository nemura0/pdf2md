import CoreGraphics

/// Symbols from a font that can't be turned into text, like the check marks of LaTeX's `bbding`.
/// They aren't in the text layer at all, and a table of check marks with no marks says nothing.
enum SymbolGlyphs {
    /// The font embeds names like `enc-34`, so nothing in the PDF says what a glyph is.
    /// Measured on a real book: `\CheckmarkBold` is code 34.
    private static let known: [String: [Int: String]] = ["bbding": [34: "✔"]]
    /// Some symbol stood here, and saying so is more faithful than leaving a blank.
    private static let unknown = "■"
    private static let space = 32
    private static let heightShare = 0.8
    /// Each run is compared with every word on the page. A real table has a few dozen.
    private static let maximumRuns = 2000

    static func words(runs: [TextRun], text: [Word]) -> [Word] {
        runs.filter { !$0.symbolCodes.isEmpty && $0.isHorizontal }.prefix(maximumRuns).compactMap {
            run in
            let codes = run.symbolCodes.filter { $0 != space }
            let rect = CGRect(
                x: run.originX,
                y: run.baseline - run.size * heightShare,
                width: max(run.endX - run.originX, 0),
                height: run.size
            )
            // If PDFKit did read this font after all, its word is already there.
            guard !codes.isEmpty, !text.contains(where: { $0.rect.intersects(rect) }) else {
                return nil
            }
            let symbols = known[run.style.name.lowercased()] ?? [:]
            return Word(
                text: codes.map { symbols[$0] ?? unknown }.joined(),
                rect: rect,
                baseline: run.baseline,
                size: run.size,
                font: run.style
            )
        }
    }
}

import CoreGraphics
import Foundation

@testable import PDF2MDKit

extension FontStyle {
    static let body = FontStyle(
        name: "Times-Roman",
        isBold: false,
        isItalic: false,
        isMonospace: false
    )
    static let bold = FontStyle(
        name: "Times-Bold",
        isBold: true,
        isItalic: false,
        isMonospace: false
    )
    static let mono = FontStyle(
        name: "Menlo-Regular",
        isBold: false,
        isItalic: false,
        isMonospace: true
    )
}

/// A word with geometry shaped like a PDFKit selection: `y` is the baseline, y grows downward.
func word(
    _ text: String,
    x: Double,
    y: Double,
    size: Double = 10,
    font: FontStyle = .body,
    isGlued: Bool = false
) -> Word {
    Word(
        text: text,
        rect: CGRect(
            x: x,
            y: y - size * 0.8,
            width: Double(text.count) * size * 0.5,
            height: size * 1.05
        ),
        baseline: y,
        size: size,
        font: font,
        isGlued: isGlued
    )
}

/// A line of space-separated words starting at `x`.
func line(
    _ text: String,
    x: Double = 72,
    y: Double,
    size: Double = 10,
    font: FontStyle = .body
) -> TextLine {
    TextLine(words: words(text, x: x, y: y, size: size, font: font))
}

func words(
    _ text: String,
    x: Double = 72,
    y: Double,
    size: Double = 10,
    font: FontStyle = .body
) -> [Word] {
    var cursor = x
    return text.split(separator: " ").map { part in
        let made = word(String(part), x: cursor, y: y, size: size, font: font)
        cursor = made.rect.maxX + size * 0.25
        return made
    }
}

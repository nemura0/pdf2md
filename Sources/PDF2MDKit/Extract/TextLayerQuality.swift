import Foundation

/// Decides whether a page's text layer is usable or the page needs OCR.
public enum TextLayerQuality {
    /// With this share of unusable characters, the fonts have no working Unicode map.
    private static let maximumBadShare = 0.3
    /// Little text over a page-sized image: a scan with stray text, such as a stamp.
    private static let littleText = 40
    private static let scanCoverage = 0.7

    /// Private-use bullets from Symbol and Wingdings are normal in slides.
    private static let bulletPrivateUse: ClosedRange<UInt32> = 0xF020...0xF0FF

    public static func needsOCR(text: String, pageImageCoverage: Double) -> Bool {
        var total = 0
        var bad = 0
        for scalar in text.unicodeScalars where !scalar.properties.isWhitespace {
            total += 1
            if isBad(scalar) { bad += 1 }
        }
        if total == 0 { return true }
        if Double(bad) / Double(total) > maximumBadShare { return true }
        return total < littleText && pageImageCoverage >= scanCoverage
    }

    private static func isBad(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        if value == 0xFFFD { return true }
        if scalar.properties.generalCategory == .control { return true }
        if scalar.properties.generalCategory == .privateUse {
            return !bulletPrivateUse.contains(value)
        }
        return false
    }
}

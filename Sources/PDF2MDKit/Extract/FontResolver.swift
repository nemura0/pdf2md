import CoreGraphics
import Foundation

/// A font dictionary, read once per page: its name, style and the advance widths the scanner
/// needs to find where each show operation ends.
final class ResolvedFont {
    /// Without widths (standard 14 fonts), runs get this rough advance and no reliable end.
    private static let fallbackWidth = 0.5
    private static let fixedPitchFlag = 1 << 0
    private static let italicFlag = 1 << 6
    private static let forceBoldFlag = 1 << 18
    private static let symbolicFlag = 4
    private static let boldWeight = 600.0
    private static let maximumWidthEntries = 70_000
    private static let codeRange = 0...0xFFFF

    private static let boldNames = [
        "bold", "black", "heavy", "semibold", "demi", "cmbx", "cmb10", "lmbx", "cmssbx", "-bd",
    ]
    private static let italicNames = ["italic", "oblique", "cmti", "cmmi", "cmsl", "lmri"]
    private static let monoNames = [
        "courier", "consolas", "menlo", "inconsolata", "cmtt", "typewriter", "lmtt",
        "sourcecode", "firacode", "sfmono", "andale", "lucidaconsole",
    ]

    let style: FontStyle
    let isTwoByte: Bool
    let hasReliableWidths: Bool
    /// Scale from glyph space to text space (0.001 except for Type3).
    private let glyphScale: Double
    let sizeScale: Double
    /// A symbolic font with no `ToUnicode` and no `Encoding`: PDFKit can't turn its glyphs into text.
    let hasNoTextMapping: Bool
    private let firstChar: Int
    private let widths: [Double]
    private let defaultWidth: Double
    private let cidWidths: [Int: Double]

    init(dictionary: CGPDFDictionaryRef) {
        let baseName = PDFValues.name(dictionary, "BaseFont") ?? ""
        let subtype = PDFValues.name(dictionary, "Subtype") ?? ""
        let descendant = PDFValues.array(dictionary, "DescendantFonts").flatMap {
            PDFValues.dictionary($0, 0)
        }
        let descriptor = PDFValues.dictionary(descendant ?? dictionary, "FontDescriptor")

        self.style = Self.makeStyle(name: Self.strippingSubset(baseName), descriptor: descriptor)
        self.isTwoByte = subtype == "Type0"
        self.hasNoTextMapping =
            !isTwoByte && CGPDFDictionaryGetStream(dictionary, "ToUnicode", nil) == false
            && PDFValues.name(dictionary, "Encoding") == nil
            && PDFValues.dictionary(dictionary, "Encoding") == nil
            && (descriptor.flatMap { PDFValues.integer($0, "Flags") } ?? 0) & Self.symbolicFlag != 0

        if subtype == "Type3", let matrix = PDFValues.array(dictionary, "FontMatrix"),
            let scale = PDFValues.number(matrix, 0), scale > 0
        {
            self.glyphScale = scale
            self.sizeScale = scale * 1000
        } else {
            self.glyphScale = 0.001
            self.sizeScale = 1
        }

        if let descendant {
            self.defaultWidth = PDFValues.number(descendant, "DW") ?? 1000
            self.cidWidths = Self.parseCIDWidths(PDFValues.array(descendant, "W"))
            self.firstChar = 0
            self.widths = []
            self.hasReliableWidths = true
        } else {
            let widths = PDFValues.array(dictionary, "Widths").map(Self.parseWidths) ?? []
            self.widths = widths
            let firstChar = PDFValues.integer(dictionary, "FirstChar") ?? 0
            self.firstChar = Self.codeRange.contains(firstChar) ? firstChar : 0
            self.defaultWidth =
                descriptor.flatMap { PDFValues.number($0, "MissingWidth") }
                ?? (self.style.isMonospace ? 600 : Self.fallbackWidth * 1000)
            self.cidWidths = [:]
            self.hasReliableWidths = !widths.isEmpty
        }
    }

    /// The advance for a character code, in text space units per unit of font size.
    func advance(forCode code: Int) -> Double {
        if isTwoByte {
            return (cidWidths[code] ?? defaultWidth) * glyphScale
        }
        let index = code - firstChar
        if widths.indices.contains(index) { return widths[index] * glyphScale }
        return defaultWidth * glyphScale
    }

    private static func strippingSubset(_ name: String) -> String {
        guard name.count > 7, name[name.index(name.startIndex, offsetBy: 6)] == "+" else {
            return name
        }
        return String(name.dropFirst(7))
    }

    private static func makeStyle(name: String, descriptor: CGPDFDictionaryRef?) -> FontStyle {
        let lowered = name.lowercased()
        let flags = descriptor.flatMap { PDFValues.integer($0, "Flags") } ?? 0
        let weight = descriptor.flatMap { PDFValues.number($0, "FontWeight") } ?? 0
        let angle = descriptor.flatMap { PDFValues.number($0, "ItalicAngle") } ?? 0
        return FontStyle(
            name: name,
            isBold: flags & forceBoldFlag != 0 || weight >= boldWeight
                || boldNames.contains { lowered.contains($0) },
            isItalic: flags & italicFlag != 0 || angle != 0
                || italicNames.contains { lowered.contains($0) },
            isMonospace: flags & fixedPitchFlag != 0
                || monoNames.contains { lowered.contains($0) }
                // `Mono` as a word, unlike `Monotype Corsiva`.
                || lowered.contains(/(^|[^a-z])mono($|[^a-z])|[a-z]mono($|[^a-z])/)
        )
    }

    private static func parseWidths(_ array: CGPDFArrayRef) -> [Double] {
        let count = min(CGPDFArrayGetCount(array), maximumWidthEntries)
        return (0..<count).map { PDFValues.number(array, $0) ?? 0 }
    }

    /// A character code from a file, which may hold any number at all.
    private static func code(_ array: CGPDFArrayRef, _ index: Int) -> Int? {
        guard let value = PDFValues.number(array, index), let code = Int(exactly: value.rounded()),
            codeRange.contains(code)
        else { return nil }
        return code
    }

    /// `/W` holds `c [w1 w2 ...]` and `first last w` entries.
    private static func parseCIDWidths(_ array: CGPDFArrayRef?) -> [Int: Double] {
        guard let array else { return [:] }
        var widths: [Int: Double] = [:]
        var index = 0
        let count = CGPDFArrayGetCount(array)
        while index < count, widths.count < maximumWidthEntries {
            guard let first = code(array, index) else { return widths }
            if let list = PDFValues.array(array, index + 1) {
                for offset in 0..<min(CGPDFArrayGetCount(list), maximumWidthEntries) {
                    widths[first + offset] = PDFValues.number(list, offset) ?? 0
                }
                index += 2
            } else if let last = code(array, index + 1),
                let width = PDFValues.number(array, index + 2), last >= first
            {
                for code in first...last { widths[code] = width }
                index += 3
            } else {
                return widths
            }
        }
        return widths
    }
}

/// Small wrappers over the CGPDF getters, since each needs an out parameter.
enum PDFValues {
    static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }

    static func dictionary(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dictionary, key, &value) ? value : nil
    }

    static func dictionary(_ array: CGPDFArrayRef, _ index: Int) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return CGPDFArrayGetDictionary(array, index, &value) ? value : nil
    }

    static func array(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
        var value: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(dictionary, key, &value) ? value : nil
    }

    static func array(_ array: CGPDFArrayRef, _ index: Int) -> CGPDFArrayRef? {
        var value: CGPDFArrayRef?
        return CGPDFArrayGetArray(array, index, &value) ? value : nil
    }

    static func stream(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? {
        var value: CGPDFStreamRef?
        return CGPDFDictionaryGetStream(dictionary, key, &value) ? value : nil
    }

    static func number(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Double? {
        var value: CGPDFReal = 0
        guard CGPDFDictionaryGetNumber(dictionary, key, &value), value.isFinite else { return nil }
        return Double(value)
    }

    static func number(_ array: CGPDFArrayRef, _ index: Int) -> Double? {
        var value: CGPDFReal = 0
        guard CGPDFArrayGetNumber(array, index, &value), value.isFinite else { return nil }
        return Double(value)
    }

    static func integer(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Int? {
        var value: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(dictionary, key, &value) ? value : nil
    }

    static func boolean(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Bool? {
        var value: CGPDFBoolean = 0
        return CGPDFDictionaryGetBoolean(dictionary, key, &value) ? value != 0 : nil
    }
}

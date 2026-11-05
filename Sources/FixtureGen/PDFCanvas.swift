import CoreGraphics
import CoreText
import CryptoKit
import Foundation

/// The fonts fixtures draw with. All of them ship with macOS.
enum FixtureFont: String {
    case body = "Times-Roman"
    case bodyBold = "Times-Bold"
    case bodyItalic = "Times-Italic"
    case sans = "Helvetica"
    case sansBold = "Helvetica-Bold"
    case mono = "Menlo-Regular"
    case math = "STIXTwoMath-Regular"
}

/// A thin wrapper around a CoreGraphics PDF context. Coordinates are PDF points, origin at the
/// bottom left. `y` is always a baseline.
final class PDFCanvas {
    let pageSize: CGSize
    let context: CGContext
    private let data = NSMutableData()
    private var fontCache: [String: CTFont] = [:]
    private(set) var pageCount = 0

    init(pageSize: CGSize, title: String? = nil, extraInfo: [CFString: Any] = [:]) throws {
        self.pageSize = pageSize
        var info = extraInfo
        if let title { info[kCGPDFContextTitle] = title }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                info.isEmpty ? nil : info as CFDictionary
            )
        else { throw FixtureError.contextCreationFailed("a PDF") }
        self.context = context
    }

    func beginPage() {
        context.beginPDFPage(nil)
        pageCount += 1
    }

    func endPage() {
        context.endPDFPage()
    }

    /// Closes the document and returns its bytes with dates and IDs fixed.
    func finish(label: String, normalize: Bool = true) -> Data {
        context.closePDF()
        let bytes = data as Data
        return normalize ? PDFNormalizer.fixVolatileFields(in: bytes, label: label) : bytes
    }

    @discardableResult
    func text(
        _ string: String,
        font: FixtureFont,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> CGFloat {
        let line = makeLine(string, font: font, size: size)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func width(of string: String, font: FixtureFont, size: CGFloat) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(makeLine(string, font: font, size: size), nil, nil, nil))
    }

    func rule(from start: CGPoint, to end: CGPoint, width: CGFloat = 0.6) {
        context.setLineWidth(width)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    func image(_ image: CGImage, in rect: CGRect) {
        context.draw(image, in: rect)
    }

    private func makeLine(_ string: String, font: FixtureFont, size: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: ctFont(font, size: size)
        ]
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
    }

    private func ctFont(_ font: FixtureFont, size: CGFloat) -> CTFont {
        let key = "\(font.rawValue)@\(size)"
        if let cached = fontCache[key] { return cached }
        let created = CTFontCreateWithName(font.rawValue as CFString, size, nil)
        fontCache[key] = created
        return created
    }
}

/// CoreGraphics PDFs differ between runs only in their dates and `/ID` (measured: 66 bytes in
/// the trailer area). Those fields have fixed lengths, so patching them keeps offsets valid.
enum PDFNormalizer {
    private static let fixedDateDigits = Data("20260101000000".utf8)

    static func fixVolatileFields(in pdf: Data, label: String) -> Data {
        var bytes = pdf
        overwriteDigits(in: &bytes, after: "/CreationDate (D:")
        overwriteDigits(in: &bytes, after: "/ModDate (D:")
        overwriteIdentifiers(in: &bytes, label: label)
        return bytes
    }

    /// Replaces same-length byte strings, for example font names in `/BaseFont`.
    static func replacing(_ target: String, with replacement: String, in pdf: Data) -> Data {
        precondition(target.utf8.count == replacement.utf8.count, "lengths must match: \(target)")
        var bytes = pdf
        let targetBytes = Data(target.utf8)
        let replacementBytes = Data(replacement.utf8)
        var searchStart = bytes.startIndex
        while let range = bytes.range(of: targetBytes, in: searchStart..<bytes.endIndex) {
            bytes.replaceSubrange(range, with: replacementBytes)
            searchStart = range.upperBound
        }
        return bytes
    }

    private static func overwriteDigits(in bytes: inout Data, after marker: String) {
        var searchStart = bytes.startIndex
        while let range = bytes.range(of: Data(marker.utf8), in: searchStart..<bytes.endIndex) {
            let digits = range.upperBound..<(range.upperBound + fixedDateDigits.count)
            guard digits.upperBound <= bytes.endIndex else { return }
            bytes.replaceSubrange(digits, with: fixedDateDigits)
            searchStart = digits.upperBound
        }
    }

    private static func overwriteIdentifiers(in bytes: inout Data, label: String) {
        guard let marker = bytes.range(of: Data("/ID [".utf8)) else { return }
        let digest = SHA256.hash(data: Data(label.utf8))
        let hex = Array(digest.map { String(format: "%02x", $0) }.joined().utf8)
        var index = marker.upperBound
        var written = 0
        var insideHexString = false
        while index < bytes.endIndex, bytes[index] != UInt8(ascii: "]") {
            switch bytes[index] {
            case UInt8(ascii: "<"):
                insideHexString = true
                written = 0
            case UInt8(ascii: ">"):
                insideHexString = false
            default:
                if insideHexString {
                    bytes[index] = hex[written % hex.count]
                    written += 1
                }
            }
            index += 1
        }
    }
}

/// A small deterministic generator (SplitMix64), so long fixtures don't depend on the system's
/// random source.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[Int(next() % UInt64(items.count))]
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}

/// Bitmaps embedded in fixtures: a logo, a chart and a full-page scan.
enum FixtureImages {
    static func makeBitmap(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw FixtureError.contextCreationFailed("a bitmap") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        guard let image = context.makeImage() else {
            throw FixtureError.renderFailed("a bitmap")
        }
        return image
    }

    static func logo() throws -> CGImage {
        try makeBitmap(width: 240, height: 120) { context in
            context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 10, y: 10, width: 220, height: 100))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 80, y: 20, width: 80, height: 80))
        }
    }

    static func barChart(values: [Int], seedColor: CGFloat = 0.2) throws -> CGImage {
        try makeBitmap(width: 800, height: 400) { context in
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(3)
            context.move(to: CGPoint(x: 40, y: 380))
            context.addLine(to: CGPoint(x: 40, y: 30))
            context.addLine(to: CGPoint(x: 780, y: 30))
            context.strokePath()
            for (index, value) in values.enumerated() {
                context.setFillColor(
                    CGColor(red: seedColor, green: 0.5, blue: 0.8 - seedColor / 2, alpha: 1)
                )
                let bar = CGRect(
                    x: 70 + CGFloat(index) * 110,
                    y: 30,
                    width: 80,
                    height: CGFloat(value) * 3
                )
                context.fill(bar)
            }
        }
    }
}

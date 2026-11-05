import CoreGraphics
import PDFKit

/// Renders a page upright, for OCR, table structure and crops.
struct RenderedPage {
    let image: CGImage
    /// Pixels per point.
    let scale: Double
}

enum PageRenderer {
    private static let preferredScale = 2.0
    /// Huge posters only. At this cap one render is about 100 MB, and it's freed after the page.
    private static let maximumSide = 5000.0

    static func render(_ page: PDFPage, size: CGSize) -> RenderedPage? {
        let longest = max(size.width, size.height)
        guard longest > 0, size.width.isFinite, size.height.isFinite else { return nil }
        let scale = min(preferredScale, maximumSide / longest)
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        // Without this, transparent pages come out black, and OCR reads nothing.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        // This call applies `/Rotate` and the crop box itself.
        page.draw(with: .cropBox, to: context)
        return context.makeImage().map { RenderedPage(image: $0, scale: scale) }
    }
}

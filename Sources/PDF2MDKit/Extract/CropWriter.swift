import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes crops of a rendered page to the spool, so emit never needs the PDF (A4).
enum CropWriter {
    /// Below this a photo stays PNG, where JPEG's saving is small and its artifacts show.
    private static let minimumJPEGPixels = 250_000
    private static let jpegQuality = 0.85

    /// Crops `rect`, in points, and returns the file's name, or nil if nothing could be written.
    static func write(
        _ rendered: RenderedPage,
        rect: CGRect,
        isPhoto: Bool,
        name: String,
        directory: URL
    ) throws -> String? {
        let scaled = CGRect(
            x: rect.minX * rendered.scale,
            y: rect.minY * rendered.scale,
            width: rect.width * rendered.scale,
            height: rect.height * rendered.scale
        ).integral
        let bounds = CGRect(x: 0, y: 0, width: rendered.image.width, height: rendered.image.height)
        let clipped = scaled.intersection(bounds)
        guard !clipped.isEmpty, let crop = rendered.image.cropping(to: clipped) else { return nil }

        let isJPEG = isPhoto && crop.width * crop.height >= minimumJPEGPixels
        let fileName = name + (isJPEG ? ".jpg" : ".png")
        let target = directory.appendingPathComponent(fileName)
        // Two workers can reach one image at once. The rename makes either result whole.
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString)")
        let type = (isJPEG ? UTType.jpeg : UTType.png).identifier as CFString
        guard
            let destination = CGImageDestinationCreateWithURL(
                temporary as CFURL,
                type,
                1,
                nil
            )
        else { throw ConversionFailure("couldn't write an image") }
        let properties =
            isJPEG
            ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
            : nil
        CGImageDestinationAddImage(destination, crop, properties)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            throw ConversionFailure("couldn't write an image")
        }
        guard rename(temporary.path, target.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw ConversionFailure("couldn't write an image")
        }
        return fileName
    }
}

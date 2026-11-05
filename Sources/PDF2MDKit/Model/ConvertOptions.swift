import Foundation

/// The tool's version, reported by `--version` and in the output's front matter.
public enum PDF2MDVersion {
    public static let current = "1.0.0"
}

/// When to run OCR on a page.
public enum OCRMode: String, Sendable, Codable, CaseIterable {
    /// OCR only pages without a usable text layer.
    case auto
    /// OCR every page, ignoring any text layer.
    case always
    /// Never OCR. Pages without a text layer produce no text.
    case never
}

/// What a conversion should produce, independent of how it is launched.
public struct ConvertOptions: Sendable, Codable, Equatable {
    public var outputDirectory: URL?
    public var overwrite: Bool
    public var includeImages: Bool
    public var includePageMarkers: Bool
    public var includeFrontMatter: Bool
    public var ocrMode: OCRMode

    public init(
        outputDirectory: URL? = nil,
        overwrite: Bool = false,
        includeImages: Bool = true,
        includePageMarkers: Bool = true,
        includeFrontMatter: Bool = true,
        ocrMode: OCRMode = .auto
    ) {
        self.outputDirectory = outputDirectory
        self.overwrite = overwrite
        self.includeImages = includeImages
        self.includePageMarkers = includePageMarkers
        self.includeFrontMatter = includeFrontMatter
        self.ocrMode = ocrMode
    }
}

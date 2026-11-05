import CoreGraphics
import Foundation

/// Font sizes that map to one heading level.
public struct HeadingBand: Sendable, Equatable {
    public var minSize: Double
    public var maxSize: Double
    public var level: Int

    public init(minSize: Double, maxSize: Double, level: Int) {
        self.minSize = minSize
        self.maxSize = maxSize
        self.level = level
    }
}

/// Whole-document decisions, made before the first line of output is written (ADR-0006).
public struct DocumentProfile: Sendable, Equatable {
    /// Matching tolerance around a band, in points, since sizes are rounded when counted.
    private static let sizeTolerance = 0.25
    /// Running headers are set at or below the text size, so this much larger isn't one.
    private static let numberedHeadingRatio = 1.2

    public var pageCount: Int
    public var bodySize: Double
    public var headingBands: [HeadingBand]
    public var title: DocumentTitle
    public var repeatedMarginKeys: Set<String>
    public var repeatedImageDigests: Set<String>
    public var isSlideDeck: Bool

    public init(
        pageCount: Int,
        bodySize: Double,
        headingBands: [HeadingBand],
        title: DocumentTitle,
        repeatedMarginKeys: Set<String>,
        repeatedImageDigests: Set<String>,
        isSlideDeck: Bool
    ) {
        self.pageCount = pageCount
        self.bodySize = bodySize
        self.headingBands = headingBands
        self.title = title
        self.repeatedMarginKeys = repeatedMarginKeys
        self.repeatedImageDigests = repeatedImageDigests
        self.isSlideDeck = isSlideDeck
    }

    public func headingLevel(forSize size: Double) -> Int? {
        headingBands.first { band in
            size >= band.minSize - Self.sizeTolerance && size <= band.maxSize + Self.sizeTolerance
        }?.level
    }

    /// True for a running header, footer or page number. Keys ignore digits, so `Exercise 1` to
    /// `Exercise 9` at the top of their pages look like one repeated line. Set larger than the
    /// text, with a number that changes, that is a run of headings. Measured on a synthetic PDF
    /// with `Section number N` at the top of each page, which lost every heading without this.
    public func isRunningMargin(_ line: TextLine, pageHeight: Double) -> Bool {
        Self.isRunningMargin(
            line,
            pageHeight: pageHeight,
            bodySize: bodySize,
            repeatedKeys: repeatedMarginKeys
        )
    }

    static func isRunningMargin(
        _ line: TextLine,
        pageHeight: Double,
        bodySize: Double,
        repeatedKeys: Set<String>
    ) -> Bool {
        guard MarginFilter.isInMargin(line.rect, pageHeight: pageHeight),
            repeatedKeys.contains(MarginFilter.key(for: line.text))
        else { return false }
        let isNumberedHeading =
            line.size >= bodySize * numberedHeadingRatio
            && line.text.contains(where: \.isNumber) && line.text.contains(where: \.isLetter)
        return !isNumberedHeading
    }

    /// Bold lines at body size rank below every sized heading.
    public var boldHeadingLevel: Int {
        min((headingBands.map(\.level).max() ?? 1) + 1, 4)
    }
}

/// Collects document statistics one page at a time, without keeping the pages.
public struct ProfileBuilder: Sendable {
    private static let topHeadingLevel = 2
    private static let levelCount = 3
    /// A size needs to beat body text by this much to be a heading, which matches the common
    /// 10.5 and 11.5 pair in books.
    private static let minimumHeadingRatio = 1.08
    /// Sizes this close are one style, as with 13.5 and 14 from different sources.
    private static let clusterRatio = 1.05
    /// Many long lines at a large size are a second body text, such as an intro.
    private static let maximumAverageHeadingLength = 45
    private static let minimumLinesToJudgeLength = 5
    private static let sizeRounding = 2.0
    private static let landscapeRatio = 1.1
    /// Images need the same `max(3, 30%)` as margin lines.
    private static let minimumImagePages = 3
    private static let imageRepeatShare = 0.3

    private struct SizeStats: Sendable {
        var chars = 0
        var lines = 0
    }

    private let pageCount: Int
    private var sizes: [Double: SizeStats] = [:]
    private var margins: MarginTracker
    private var imageCounts: [String: Int] = [:]
    private var landscapePages = 0
    private var firstPageLines: [TextLine] = []
    private var firstPageHeight = 0.0

    public init(pageCount: Int) {
        self.pageCount = pageCount
        self.margins = MarginTracker(pageCount: pageCount)
    }

    public mutating func add(
        pageIndex: Int,
        pageSize: CGSize,
        lines: [TextLine],
        images: [FigureCandidate]
    ) {
        let isLandscape = pageSize.width > pageSize.height * Self.landscapeRatio
        if isLandscape { landscapePages += 1 }
        for line in lines where !line.isMonospace {
            let key = Self.rounded(line.size)
            sizes[key, default: SizeStats()].chars += line.text.count
            sizes[key, default: SizeStats()].lines += 1
        }
        let keys = lines.filter { MarginFilter.isInMargin($0.rect, pageHeight: pageSize.height) }
            .map { MarginFilter.key(for: $0.text) }
        margins.add(page: pageIndex, keys: keys, isLandscape: isLandscape)
        for digest in Set(images.map(\.digest)) {
            imageCounts[digest, default: 0] += 1
        }
        if pageIndex == 0 {
            firstPageLines = lines
            firstPageHeight = pageSize.height
        }
    }

    public func finish(metadataTitle: String?, fileName: String) -> DocumentProfile {
        let body = sizes.max { ($0.value.chars, $0.key) < ($1.value.chars, $1.key) }?.key ?? 0
        let repeated = margins.repeatedKeys()
        // A running header often repeats the title, which must still count on the cover itself.
        let contentLines = firstPageLines.filter {
            !DocumentProfile.isRunningMargin(
                $0,
                pageHeight: firstPageHeight,
                bodySize: body,
                repeatedKeys: repeated
            )
        }
        let title = TitleResolver.resolve(
            metadataTitle: metadataTitle,
            firstPageLines: contentLines,
            bodySize: body,
            fileName: fileName
        )
        return DocumentProfile(
            pageCount: pageCount,
            bodySize: body,
            headingBands: headingBands(bodySize: body, title: title),
            title: title,
            repeatedMarginKeys: repeated,
            repeatedImageDigests: repeatedImages(),
            isSlideDeck: landscapePages * 2 > pageCount
        )
    }

    /// Ranks larger sizes from the top. Title lines don't count, or a once-used cover size would
    /// take `##` from every real section.
    private func headingBands(bodySize: Double, title: DocumentTitle) -> [HeadingBand] {
        var stats = sizes
        for line in firstPageLines where title.lineTexts.contains(line.text) {
            let key = Self.rounded(line.size)
            stats[key]?.lines -= 1
            stats[key]?.chars -= line.text.count
        }
        let candidates = stats.filter { size, stat in
            guard size >= bodySize * Self.minimumHeadingRatio, stat.lines > 0 else { return false }
            let isLongText =
                stat.lines >= Self.minimumLinesToJudgeLength
                && stat.chars / stat.lines > Self.maximumAverageHeadingLength
            return !isLongText
        }.keys.sorted(by: >)

        var clusters: [(min: Double, max: Double)] = []
        for size in candidates {
            if let last = clusters.last, last.min / size <= Self.clusterRatio {
                clusters[clusters.count - 1].min = size
            } else {
                clusters.append((size, size))
            }
        }
        return clusters.enumerated().map { index, cluster in
            let level = min(
                Self.topHeadingLevel + index,
                Self.topHeadingLevel + Self.levelCount - 1
            )
            return HeadingBand(minSize: cluster.min, maxSize: cluster.max, level: level)
        }
    }

    private func repeatedImages() -> Set<String> {
        let threshold = max(
            Self.minimumImagePages,
            Int((Double(pageCount) * Self.imageRepeatShare).rounded(.up))
        )
        return Set(imageCounts.filter { $0.value >= threshold }.keys)
    }

    private static func rounded(_ size: Double) -> Double {
        (size * sizeRounding).rounded() / sizeRounding
    }
}

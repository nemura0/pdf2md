import CoreGraphics
import Foundation

/// Font sizes that map to one heading level.
public struct HeadingBand: Sendable, Equatable {
    public var minSize: Double
    public var maxSize: Double
    public var level: Int
    /// The outline's headings at this size are bold, so regular text at this size isn't one.
    public var requiresBold: Bool

    public init(minSize: Double, maxSize: Double, level: Int, requiresBold: Bool = false) {
        self.minSize = minSize
        self.maxSize = maxSize
        self.level = level
        self.requiresBold = requiresBold
    }
}

/// Whole-document decisions, made before the first line of output is written (ADR-0006).
public struct DocumentProfile: Sendable, Equatable {
    /// Matching tolerance around a band, in points, since sizes are rounded when counted.
    private static let sizeTolerance = 0.25
    /// Running headers are set at or below the text size, so this much larger isn't one.
    private static let numberedHeadingRatio = 1.2
    /// A heading beats the text by this much. It matches the common 10.5 and 11.5 pair in books.
    static let minimumHeadingRatio = 1.08
    private static let runningHeadRatio = 1.05
    private static let runningHeadTolerance = 1.0
    private static let deepestSizedLevel = 4
    private static let deepestOutlineLevel = 6

    public var pageCount: Int
    public var bodySize: Double
    public var headingBands: [HeadingBand]
    public var title: DocumentTitle
    public var repeatedMarginKeys: Set<String>
    public var repeatedImageDigests: Set<String>
    public var isSlideDeck: Bool
    /// By page. Empty unless the outline matched the pages (ADR-0009).
    public var outlineEntriesByPage: [Int: [OutlineEntry]]
    /// Where the running header sits on the page, when one is found by its place.
    public var runningHeadBaseline: Double?

    public init(
        pageCount: Int,
        bodySize: Double,
        headingBands: [HeadingBand],
        title: DocumentTitle,
        repeatedMarginKeys: Set<String>,
        repeatedImageDigests: Set<String>,
        isSlideDeck: Bool,
        outlineEntriesByPage: [Int: [OutlineEntry]] = [:],
        runningHeadBaseline: Double? = nil
    ) {
        self.pageCount = pageCount
        self.bodySize = bodySize
        self.headingBands = headingBands
        self.title = title
        self.repeatedMarginKeys = repeatedMarginKeys
        self.repeatedImageDigests = repeatedImageDigests
        self.isSlideDeck = isSlideDeck
        self.outlineEntriesByPage = outlineEntriesByPage
        self.runningHeadBaseline = runningHeadBaseline
    }

    public func headingLevel(forSize size: Double) -> Int? {
        headingLevel(size: size, isBold: true)
    }

    public func headingLevel(for line: TextLine) -> Int? {
        headingLevel(size: line.size, isBold: line.isBold)
    }

    private func headingLevel(size: Double, isBold: Bool) -> Int? {
        headingBands.first { band in
            size >= band.minSize - Self.sizeTolerance && size <= band.maxSize + Self.sizeTolerance
                && (isBold || !band.requiresBold)
        }?.level
    }

    public func outlineEntries(onPage page: Int) -> [OutlineEntry] {
        outlineEntriesByPage[page] ?? []
    }

    var minimumHeadingSize: Double { bodySize * Self.minimumHeadingRatio }

    /// True for a running header, footer or page number. Keys ignore digits, so `Exercise 1` to
    /// `Exercise 9` at the top of their pages look like one repeated line. Set larger than the
    /// text, with a number that changes, that is a run of headings. Measured on a synthetic PDF
    /// with `Section number N` at the top of each page, which lost every heading without this.
    public func isRunningMargin(_ line: TextLine, pageHeight: Double) -> Bool {
        Self.isRunningMargin(
            line,
            pageHeight: pageHeight,
            bodySize: bodySize,
            repeatedKeys: repeatedMarginKeys,
            runningHeadBaseline: runningHeadBaseline
        )
    }

    static func isRunningMargin(
        _ line: TextLine,
        pageHeight: Double,
        bodySize: Double,
        repeatedKeys: Set<String>,
        runningHeadBaseline: Double?
    ) -> Bool {
        // A closing brace near the bottom repeats on many pages of a programming book.
        guard !line.isMonospace, MarginFilter.isInMargin(line.rect, pageHeight: pageHeight)
        else { return false }
        // Books name the current section up there, so the words change every few pages and only
        // the place repeats. Large or bold text in that place is a heading that happens to start
        // its page, and a repeated bold header is still caught by its words below.
        if let runningHeadBaseline,
            abs(line.baseline - runningHeadBaseline) <= runningHeadTolerance,
            line.size <= bodySize * runningHeadRatio, !line.isBold
        {
            return true
        }
        guard repeatedKeys.contains(MarginFilter.key(for: line.text)) else { return false }
        let isNumberedHeading =
            line.size >= bodySize * numberedHeadingRatio
            && line.text.contains(where: \.isNumber) && line.text.contains(where: \.isLetter)
        return !isNumberedHeading
    }

    /// Bold lines at body size rank below every sized heading.
    public var boldHeadingLevel: Int {
        let deepest =
            outlineEntriesByPage.isEmpty ? Self.deepestSizedLevel : Self.deepestOutlineLevel
        return min((headingBands.map(\.level).max() ?? 1) + 1, deepest)
    }
}

/// Collects document statistics one page at a time, without keeping the pages.
public struct ProfileBuilder: Sendable {
    private static let topHeadingLevel = 2
    private static let levelCount = 3
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

    /// In a document this long, a size used on one page is a cover or a one-off, and ranking it
    /// would push every real heading down a level. In a short one it can be the only heading.
    private static let minimumPagesToJudgeRarity = 10
    private static let minimumHeadingSizePages = 2
    /// An outline counts when this many of its entries, and this share, match the pages.
    private static let minimumOutlineMatches = 3
    private static let minimumOutlineShare = 0.5
    private static let minimumStyleRatio = 4
    private static let runningHeadGapRatio = 1.5
    private static let runningHeadSeparatedShare = 0.8

    private struct SizeStats: Sendable {
        var chars = 0
        var lines = 0
        /// Lines with a letter. A chapter number alone can't be what a size is used for.
        var wordLines = 0
        var pages = 0
        var lastPage = -1
    }

    private struct OutlineSample: Hashable {
        var size: Double
        var isBold: Bool
        var level: Int
    }

    private struct TopLine {
        var count = 0
        var separated = 0
    }

    private let pageCount: Int
    private let outline: [OutlineEntry]
    private let outlineByPage: [Int: [OutlineEntry]]
    private var outlineSamples: [OutlineSample: Int] = [:]
    private var topLines: [Double: TopLine] = [:]
    private var sizes: [Double: SizeStats] = [:]
    private var margins: MarginTracker
    private var imageCounts: [String: Int] = [:]
    private var landscapePages = 0
    private var firstPageLines: [TextLine] = []
    private var firstPageHeight = 0.0

    public init(pageCount: Int, outline: [OutlineEntry] = []) {
        self.pageCount = pageCount
        self.outline = outline
        self.outlineByPage = Dictionary(grouping: outline, by: \.pageIndex)
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
            var stats = sizes[key] ?? SizeStats()
            stats.chars += line.text.count
            stats.lines += 1
            if line.text.contains(where: \.isLetter) { stats.wordLines += 1 }
            if stats.lastPage != pageIndex { stats.pages += 1 }
            stats.lastPage = pageIndex
            sizes[key] = stats
        }
        addTopLine(of: lines)
        addOutlineSamples(pageIndex: pageIndex, lines: lines)
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

    /// The body size isn't known until the end, so this takes every line that reads as an entry,
    /// and `outlineBands` looks at their sizes once it is.
    private mutating func addOutlineSamples(pageIndex: Int, lines: [TextLine]) {
        guard let entries = outlineByPage[pageIndex] else { return }
        let marked = OutlineMatcher.marking(
            lines,
            with: entries,
            minimumSize: 0,
            joinsNumbers: false
        )
        for line in marked {
            guard let level = line.outlineLevel else { continue }
            let sample = OutlineSample(
                size: Self.rounded(line.size),
                isBold: line.isBold,
                level: level
            )
            outlineSamples[sample, default: 0] += 1
        }
    }

    /// A running header is the page's top line, always in one place, with space below it.
    private mutating func addTopLine(of lines: [TextLine]) {
        guard let first = lines.min(by: { $0.baseline < $1.baseline }),
            let next = lines.map(\.baseline).filter({ $0 > first.baseline + 1 }).min()
        else { return }
        var top = topLines[first.baseline.rounded()] ?? TopLine()
        top.count += 1
        if next - first.baseline >= first.size * Self.runningHeadGapRatio { top.separated += 1 }
        topLines[first.baseline.rounded()] = top
    }

    private func runningHeadBaseline() -> Double? {
        let threshold = MarginTracker.threshold(forPageCount: pageCount)
        return
            topLines
            .filter { _, top in
                top.count >= threshold
                    && Double(top.separated) >= Double(top.count) * Self.runningHeadSeparatedShare
            }
            .max { ($0.value.count, $0.key) < ($1.value.count, $1.key) }?.key
    }

    /// The sizes and weights of the headings an outline names, or nil if it doesn't match the
    /// pages. Each size takes the level most of its headings have (ADR-0009).
    private func outlineBands(bodySize: Double) -> [HeadingBand]? {
        let minimumSize = bodySize * DocumentProfile.minimumHeadingRatio
        let samples = outlineSamples.filter { $0.key.size >= minimumSize || $0.key.isBold }
        let matches = samples.values.reduce(0, +)
        guard matches >= Self.minimumOutlineMatches,
            Double(matches) >= Double(outline.count) * Self.minimumOutlineShare
        else { return nil }
        return Self.bands(from: samples)
    }

    /// Each size and weight takes the level most of its headings have. A weight that's rare at its
    /// size is left out. Headings holding a word of code aren't quite bold, and without this every
    /// regular line at that size would become a heading: measured on `7.16. final`, among 101 bold
    /// section headings, which made a sentence set large into one.
    private static func bands(from samples: [OutlineSample: Int]) -> [HeadingBand] {
        var bestByStyle: [OutlineSample: (level: Int, count: Int)] = [:]
        var countByStyle: [OutlineSample: Int] = [:]
        for (sample, count) in samples {
            let style = OutlineSample(size: sample.size, isBold: sample.isBold, level: 0)
            countByStyle[style, default: 0] += count
            let best = bestByStyle[style]
            if best == nil || (count, -sample.level) > (best?.count ?? 0, -(best?.level ?? 0)) {
                bestByStyle[style] = (sample.level, count)
            }
        }
        let bands = bestByStyle.compactMap { style, best -> HeadingBand? in
            let other = OutlineSample(size: style.size, isBold: !style.isBold, level: 0)
            let share = countByStyle[style, default: 0] * minimumStyleRatio
            guard share >= countByStyle[other, default: 0] else { return nil }
            return HeadingBand(
                minSize: style.size,
                maxSize: style.size,
                level: best.level,
                requiresBold: style.isBold
            )
        }
        return bands.sorted { ($0.minSize, $0.level) > ($1.minSize, $1.level) }
    }

    public func finish(metadataTitle: String?, fileName: String) -> DocumentProfile {
        let body = sizes.max { ($0.value.chars, $0.key) < ($1.value.chars, $1.key) }?.key ?? 0
        let repeated = margins.repeatedKeys()
        let isSlideDeck = landscapePages * 2 > pageCount
        let runningHead = isSlideDeck ? nil : runningHeadBaseline()
        // A running header often repeats the title, which must still count on the cover itself.
        let contentLines = firstPageLines.filter {
            !DocumentProfile.isRunningMargin(
                $0,
                pageHeight: firstPageHeight,
                bodySize: body,
                repeatedKeys: repeated,
                runningHeadBaseline: runningHead
            )
        }
        let title = TitleResolver.resolve(
            metadataTitle: metadataTitle,
            firstPageLines: contentLines,
            bodySize: body,
            fileName: fileName
        )
        let outlined = isSlideDeck ? nil : outlineBands(bodySize: body)
        return DocumentProfile(
            pageCount: pageCount,
            bodySize: body,
            headingBands: outlined ?? headingBands(bodySize: body, title: title),
            title: title,
            repeatedMarginKeys: repeated,
            repeatedImageDigests: repeatedImages(),
            isSlideDeck: isSlideDeck,
            outlineEntriesByPage: outlined == nil ? [:] : outlineByPage,
            runningHeadBaseline: runningHead
        )
    }

    /// Ranks larger sizes from the top. Title lines don't count, or a once-used cover size would
    /// take `##` from every real section, and neither do sizes that are rare in a long document.
    private func headingBands(bodySize: Double, title: DocumentTitle) -> [HeadingBand] {
        var stats = sizes
        for line in firstPageLines where title.lineTexts.contains(line.text) {
            let key = Self.rounded(line.size)
            stats[key]?.lines -= 1
            stats[key]?.chars -= line.text.count
            stats[key]?.wordLines -= 1
        }
        let judgesRarity = pageCount >= Self.minimumPagesToJudgeRarity
        let candidates = stats.filter { size, stat in
            guard size >= bodySize * DocumentProfile.minimumHeadingRatio, stat.wordLines > 0,
                !judgesRarity || stat.pages >= Self.minimumHeadingSizePages
            else { return false }
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

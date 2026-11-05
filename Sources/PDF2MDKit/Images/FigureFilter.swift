import CoreGraphics
import Foundation

/// Which image placements are figures. Whole-document repetition is decided later, at emit.
public enum FigureFilter {
    /// Backgrounds and the page image of a searchable scan cover the page.
    private static let pageCoverageShare = 0.85
    private static let scanCoverage = 0.7

    public static func isPageSized(_ rect: CGRect, pageSize: CGSize) -> Bool {
        let area = rect.intersection(CGRect(origin: .zero, size: pageSize))
        guard !area.isNull, pageSize.width > 0, pageSize.height > 0 else { return false }
        return (area.width * area.height) / (pageSize.width * pageSize.height) >= pageCoverageShare
    }

    /// The share of the page its images cover. A sum, because scanners also cut pages in strips.
    public static func imageCoverage(_ figures: [FigureCandidate], pageSize: CGSize) -> Double {
        let page = CGRect(origin: .zero, size: pageSize)
        guard pageSize.width > 0, pageSize.height > 0 else { return 0 }
        let covered = figures.reduce(0.0) { total, figure in
            let area = figure.rect.intersection(page)
            return total + (area.isNull ? 0 : Double(area.width * area.height))
        }
        return min(covered / Double(pageSize.width * pageSize.height), 1)
    }

    /// The figures worth cropping. Nothing from a page that is a scan: its images are the page.
    public static func kept(
        _ figures: [FigureCandidate],
        pageSize: CGSize,
        isOCR: Bool
    ) -> [FigureCandidate] {
        if isOCR, imageCoverage(figures, pageSize: pageSize) >= scanCoverage { return [] }
        return kept(figures, pageSize: pageSize)
    }

    /// Drops page-sized images and identical placements of one image on one page.
    public static func kept(_ figures: [FigureCandidate], pageSize: CGSize) -> [FigureCandidate] {
        var seen: Set<String> = []
        return figures.filter { figure in
            !isPageSized(figure.rect, pageSize: pageSize) && seen.insert(figure.digest).inserted
        }
    }
}

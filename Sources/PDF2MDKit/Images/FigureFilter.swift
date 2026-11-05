import CoreGraphics
import Foundation

/// Which image placements are figures. Whole-document repetition is decided later, at emit.
public enum FigureFilter {
    /// Backgrounds and the page image of a searchable scan cover the page.
    private static let pageCoverageShare = 0.85

    public static func isPageSized(_ rect: CGRect, pageSize: CGSize) -> Bool {
        let area = rect.intersection(CGRect(origin: .zero, size: pageSize))
        guard !area.isNull, pageSize.width > 0, pageSize.height > 0 else { return false }
        return (area.width * area.height) / (pageSize.width * pageSize.height) >= pageCoverageShare
    }

    /// The share of the page covered by its largest image, for the OCR gate.
    public static func imageCoverage(_ figures: [FigureCandidate], pageSize: CGSize) -> Double {
        let page = CGRect(origin: .zero, size: pageSize)
        guard pageSize.width > 0, pageSize.height > 0 else { return 0 }
        let largest =
            figures.map { figure -> Double in
                let area = figure.rect.intersection(page)
                return area.isNull ? 0 : Double(area.width * area.height)
            }.max() ?? 0
        return largest / Double(pageSize.width * pageSize.height)
    }

    /// Drops page-sized images and identical placements of one image on one page.
    public static func kept(_ figures: [FigureCandidate], pageSize: CGSize) -> [FigureCandidate] {
        var seen: Set<String> = []
        return figures.filter { figure in
            !isPageSized(figure.rect, pageSize: pageSize) && seen.insert(figure.digest).inserted
        }
    }
}

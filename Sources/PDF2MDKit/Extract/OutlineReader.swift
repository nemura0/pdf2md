import Foundation
import PDFKit

/// Reads a document's outline. Only preflight calls this, on its own short-lived document (A3).
enum OutlineReader {
    /// Far beyond a real outline. The largest of the books we've read has hundreds of entries, and
    /// a malformed one can't make the walk unbounded.
    private static let maximumEntries = 20_000
    private static let maximumDepth = 16

    static func entries(of document: PDFDocument) -> [OutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [OutlineEntry] = []
        walk(root, depth: 0, document: document, into: &entries)
        return entries
    }

    private static func walk(
        _ node: PDFOutline,
        depth: Int,
        document: PDFDocument,
        into entries: inout [OutlineEntry]
    ) {
        guard depth < maximumDepth else { return }
        for index in 0..<node.numberOfChildren {
            guard entries.count < maximumEntries, let child = node.child(at: index) else { return }
            if let entry = entry(for: child, depth: depth, document: document) {
                entries.append(entry)
            }
            walk(child, depth: depth + 1, document: document, into: &entries)
        }
    }

    private static func entry(
        for item: PDFOutline,
        depth: Int,
        document: PDFDocument
    ) -> OutlineEntry? {
        guard let page = item.destination?.page, let raw = item.label else { return nil }
        let pageIndex = document.index(for: page)
        let label = OutlineLabel.clean(raw)
        guard pageIndex >= 0, pageIndex < document.pageCount, !label.isEmpty else { return nil }
        return OutlineEntry(pageIndex: pageIndex, depth: depth, label: label)
    }
}

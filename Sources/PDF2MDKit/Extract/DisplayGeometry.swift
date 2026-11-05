import CoreGraphics
import PDFKit

/// Maps PDF user space to display space: rotated, cropped, points, origin top left, y down.
/// `selection.bounds(for:)` stays in unrotated page space (measured: ADR-0003), so all geometry
/// goes through here.
struct DisplayGeometry {
    let transform: CGAffineTransform
    let size: CGSize

    init(page: PDFPage) {
        let bounds = page.bounds(for: .cropBox).applying(page.transform(for: .cropBox))
        self.size = CGSize(width: abs(bounds.width), height: abs(bounds.height))
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: self.size.height)
        self.transform = page.transform(for: .cropBox).concatenating(flip)
    }

    func convert(_ rect: CGRect) -> CGRect {
        rect.applying(transform)
    }
}

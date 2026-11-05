import CoreGraphics

/// One line from OCR. Rects are normalized to the page, origin top left, y down.
public struct RecognizedLine: Sendable, Equatable {
    public var text: String
    public var rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

/// One table cell from Vision. Ranges are zero-based and inclusive, because cells can span.
public struct RecognizedCell: Sendable, Equatable {
    public var text: String
    public var rect: CGRect
    public var rows: ClosedRange<Int>
    public var columns: ClosedRange<Int>

    public init(text: String, rect: CGRect, rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.text = text
        self.rect = rect
        self.rows = rows
        self.columns = columns
    }
}

public struct RecognizedTable: Sendable, Equatable {
    public var rect: CGRect
    public var cells: [RecognizedCell]

    public init(rect: CGRect, cells: [RecognizedCell]) {
        self.rect = rect
        self.cells = cells
    }
}

/// What the recognizer saw on a page, as plain values, so nothing from Vision reaches the model.
public struct RecognizedPage: Sendable, Equatable {
    public var lines: [RecognizedLine]
    public var tables: [RecognizedTable]

    public init(lines: [RecognizedLine], tables: [RecognizedTable]) {
        self.lines = lines
        self.tables = tables
    }
}

/// The seam around Vision, so structure tests don't need a model load.
public protocol DocumentRecognizing: Sendable {
    func recognize(_ image: CGImage) async throws -> RecognizedPage
}

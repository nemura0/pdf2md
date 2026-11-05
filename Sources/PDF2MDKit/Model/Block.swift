/// One list entry. `marker` is what Markdown shows: `-` or a number such as `3.`.
public struct ListItem: Sendable, Equatable {
    public var depth: Int
    public var marker: String
    public var text: String

    public init(depth: Int, marker: String, text: String) {
        self.depth = depth
        self.marker = marker
        self.text = text
    }
}

/// A piece of document structure. Text in blocks is already escaped Markdown.
public enum Block: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([ListItem])
    case code([String])
    case displayMath(String)
    case table([[String]])
    case figure(path: String)
}

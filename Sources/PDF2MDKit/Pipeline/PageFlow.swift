/// Writes blocks across page boundaries, holding back a page's last paragraph in case the next
/// page continues it. Word-processor documents and books split paragraphs at page breaks all the
/// time, and a marker in mid-sentence costs an LLM the sentence. Markers passed while a paragraph
/// is held come right after it.
struct PageFlow {
    private var held: String?
    private var pendingMarkers: [String] = []

    mutating func write(
        _ blocks: [Block],
        pageMarker: String?,
        to stream: inout MarkdownStream
    ) throws {
        var remaining = blocks[...]
        if let marker = pageMarker { pendingMarkers.append(marker) }
        if let text = held, case .paragraph(let next)? = remaining.first,
            Self.continues(text, with: next)
        {
            held = Self.join(text, next)
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return }
        }
        try flush(to: &stream)

        for (offset, block) in remaining.enumerated() {
            if offset == remaining.count - 1, case .paragraph(let text) = block {
                held = text
            } else {
                try stream.write(block: MarkdownRenderer.render(block))
            }
        }
    }

    mutating func finish(to stream: inout MarkdownStream) throws {
        try flush(to: &stream)
    }

    private mutating func flush(to stream: inout MarkdownStream) throws {
        if let text = held { try stream.write(block: text) }
        held = nil
        for marker in pendingMarkers { try stream.write(block: marker) }
        pendingMarkers = []
    }

    /// True when the text stops mid-sentence and the next page starts in lowercase.
    private static func continues(_ text: String, with next: String) -> Bool {
        guard let last = text.last, let first = next.first else { return false }
        return !".:!?)".contains(last) && first.isLowercase
    }

    private static func join(_ text: String, _ next: String) -> String {
        if text.hasSuffix("-"), text.count > 1 { return String(text.dropLast()) + next }
        return text + " " + next
    }
}

/// Writes blocks across page boundaries, holding back a page's last paragraph or list in case the
/// next page continues it. Word-processor documents and books split paragraphs at page breaks all
/// the time, and a marker in mid-sentence costs an LLM the sentence. Markers and footnotes passed
/// while a block is held come right after it, in the order the pages had them. A page with nothing
/// on it, such as LaTeX's blank left-hand pages, has no marker: there is nothing for one to point at.
struct PageFlow {
    private var held: Block?
    private var pending: [String] = []

    mutating func write(
        _ blocks: [Block],
        pageMarker: String?,
        to stream: inout MarkdownStream
    ) throws {
        guard !blocks.isEmpty else { return }
        if let marker = pageMarker { pending.append(marker) }
        let notes = blocks.reversed().prefix { $0.isFootnote }.reversed()
            .map(MarkdownRenderer.render)
        var remaining = blocks.dropLast(notes.count)
        if let block = held, let text = block.closingText,
            case .paragraph(let next)? = remaining.first, Self.continues(text, with: next)
        {
            held = block.continued(with: next)
            remaining = remaining.dropFirst()
            if remaining.isEmpty {
                pending += notes
                return
            }
        }
        try flush(to: &stream)

        for (offset, block) in remaining.enumerated() {
            if offset == remaining.count - 1, block.closingText != nil {
                held = block
            } else {
                try stream.write(block: MarkdownRenderer.render(block))
            }
        }
        pending += notes
    }

    mutating func finish(to stream: inout MarkdownStream) throws {
        try flush(to: &stream)
    }

    private mutating func flush(to stream: inout MarkdownStream) throws {
        if let block = held { try stream.write(block: MarkdownRenderer.render(block)) }
        held = nil
        for block in pending { try stream.write(block: block) }
        pending = []
    }

    /// True when the text stops mid-sentence and the next page starts in lowercase.
    private static func continues(_ text: String, with next: String) -> Bool {
        guard let last = text.last, let first = next.first else { return false }
        return !".:!?)".contains(last) && first.isLowercase
    }

    fileprivate static func join(_ text: String, _ next: String) -> String {
        if text.hasSuffix("-"), text.count > 1 { return String(text.dropLast()) + next }
        return text + " " + next
    }
}

extension Block {
    fileprivate var isFootnote: Bool {
        if case .footnote = self { return true }
        return false
    }

    /// The text the next page could carry on, in the blocks that can run over a page break.
    fileprivate var closingText: String? {
        switch self {
        case .paragraph(let text): text
        case .list(let items): items.last?.text
        default: nil
        }
    }

    fileprivate func continued(with next: String) -> Block {
        switch self {
        case .paragraph(let text):
            return .paragraph(PageFlow.join(text, next))
        case .list(let items):
            guard let last = items.last else { return self }
            var joined = last
            joined.text = PageFlow.join(last.text, next)
            return .list(items.dropLast() + [joined])
        default:
            return self
        }
    }
}

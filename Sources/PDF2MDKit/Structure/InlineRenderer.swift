/// Renders a line's words to escaped Markdown, wrapping monospace runs as inline code.
public enum InlineRenderer {
    /// A whole line, with its math as `$...$`. Code stays code, where `$` means nothing.
    public static func render(line: TextLine) -> String {
        render(line.words, in: line)
    }

    /// Some of a line's words, such as a list item without its marker. Scripts are measured
    /// against the line they're on.
    public static func render(_ words: [Word], in line: TextLine) -> String {
        guard !words.contains(where: \.font.isMonospace),
            let math = MathSpans.render(words, baseline: line.baseline, size: line.size)
        else { return render(words) }
        return math
    }

    /// A line opening a paragraph or a list item. A bold term running into plain text is how
    /// `description` lists and many definitions are set, so that bold carries structure.
    public static func renderOpening(_ words: [Word], in line: TextLine) -> String {
        let lead = words.prefix { $0.font.isBold && !$0.font.isMonospace }
        guard !lead.isEmpty, lead.count < words.count else { return render(words, in: line) }
        let rest = Array(words.dropFirst(lead.count))
        let separator = rest[0].isGlued ? "" : " "
        let body = isAllMonospace(rest) ? code(rest) : render(rest, in: line)
        return "**" + render(Array(lead), in: line) + "**" + separator + body
    }

    /// Words that are all code, as a code span.
    public static func code(_ words: [Word]) -> String {
        codeSpan(TextNormalizer.normalize(joined(words)))
    }

    public static func render(_ words: [Word]) -> String {
        var output = ""
        var codeRun: [Word] = []

        func flushCode() {
            guard !codeRun.isEmpty else { return }
            let code = TextNormalizer.normalize(joined(codeRun))
            output += codeSpan(code)
            codeRun = []
        }

        for word in words {
            if word.font.isMonospace, !isAllMonospace(words) {
                if codeRun.isEmpty, !word.isGlued, !output.isEmpty { output += " " }
                codeRun.append(word)
                continue
            }
            flushCode()
            if !word.isGlued, !output.isEmpty { output += " " }
            output += escape(TextNormalizer.normalize(word.text))
        }
        flushCode()
        return output
    }

    /// CommonMark: the fence must differ from every backtick run inside, and a span that starts
    /// or ends with a backtick is padded with one space, which readers strip.
    private static func codeSpan(_ code: String) -> String {
        let longestRun = code.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: longestRun + 1)
        let padding = code.hasPrefix("`") || code.hasSuffix("`") ? " " : ""
        return fence + padding + code + padding + fence
    }

    private static func isAllMonospace(_ words: [Word]) -> Bool {
        words.allSatisfy(\.font.isMonospace)
    }

    private static func joined(_ words: [Word]) -> String {
        words.enumerated().reduce(into: "") { text, item in
            if item.offset > 0, !item.element.isGlued { text += " " }
            text += item.element.text
        }
    }

    /// Escapes what would change meaning in running text. Underscores inside words stay, since
    /// GFM leaves them alone, and `snake_case` is common here and costs tokens to escape.
    public static func escape(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            switch character {
            case "\\", "*", "`", "[", "]", "<", "$", "|":
                output.append("\\")
            case "_":
                let isInsideWord =
                    index > 0 && index < characters.count - 1
                    && characters[index - 1].isLetterOrNumber
                    && characters[index + 1].isLetterOrNumber
                if !isInsideWord { output.append("\\") }
            default:
                break
            }
            output.append(character)
        }
        return output
    }

    /// Escapes a block's start when it would otherwise read as a heading, quote or list.
    public static func escapingBlockStart(_ text: String) -> String {
        if text.wholeMatch(of: /(#{1,6}|>|[-+]|\d{1,9}[.)])(\s.*)?/) != nil
            || text.hasPrefix(">")
        {
            return "\\" + text
        }
        return text
    }
}

extension Character {
    fileprivate var isLetterOrNumber: Bool { isLetter || isNumber }
}

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

    public static func render(_ words: [Word]) -> String {
        var output = ""
        var codeRun: [Word] = []

        func flushCode() {
            guard !codeRun.isEmpty else { return }
            let code = TextNormalizer.normalize(joined(codeRun))
            let fence = code.contains("`") ? "``" : "`"
            output += fence + code + fence
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

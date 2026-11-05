import Foundation

/// Blocks to Markdown text.
public enum MarkdownRenderer {
    public static func render(_ block: Block) -> String {
        switch block {
        case .heading(let level, let text):
            String(repeating: "#", count: level) + " " + text
        case .paragraph(let text):
            text
        case .list(let items):
            renderList(items)
        case .code(let lines):
            renderFence(lines)
        case .labels(let lines):
            renderFence(lines, info: "text")
        case .displayMath(let latex):
            "$$\n\(latex)\n$$"
        case .table(let rows):
            renderTable(rows)
        case .figure(let path):
            "![Figure](\(percentEncoded(path)))"
        case .footnote(let label, let text):
            label.map { "[^\($0)]: \(text)" } ?? text
        }
    }

    /// Children indent to their parent's text, whose offset depends on the marker's width.
    private static func renderList(_ items: [ListItem]) -> String {
        var offsets = [0]
        var lines: [String] = []
        for item in items {
            let depth = min(item.depth, offsets.count - 1)
            offsets = Array(offsets[...depth])
            offsets.append(offsets[depth] + item.marker.count + 1)
            lines.append(
                String(repeating: " ", count: offsets[depth]) + item.marker + " " + item.text
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func renderFence(_ lines: [String], info: String = "") -> String {
        let longestRun = lines.map(longestBacktickRun).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longestRun + 1))
        return ([fence + info] + lines + [fence]).joined(separator: "\n")
    }

    private static func longestBacktickRun(in line: String) -> Int {
        var longest = 0
        var current = 0
        for character in line {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    private static func renderTable(_ rows: [[String]]) -> String {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }
        let rendered = rows.map { row -> String in
            let cells = (0..<columnCount).map { index -> String in
                index < row.count ? escapeCell(row[index]) : ""
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }
        let separator =
            "| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |"
        return ([rendered[0], separator] + rendered.dropFirst()).joined(separator: "\n")
    }

    /// Cells usually arrive escaped by `InlineRenderer`, and a doubled backslash would end the
    /// cell at the pipe.
    private static func escapeCell(_ cell: String) -> String {
        var output = ""
        var isEscaped = false
        for character in cell {
            if character.isNewline {
                output.append(" ")
            } else {
                if character == "|", !isEscaped { output.append("\\") }
                output.append(character)
            }
            isEscaped = character == "\\" && !isEscaped
        }
        return output
    }

    private static func percentEncoded(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}

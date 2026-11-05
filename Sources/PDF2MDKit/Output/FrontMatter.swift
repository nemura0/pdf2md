/// The YAML block at the top of the output. Strings are always double-quoted, since titles can
/// hold colons, quotes and anything else.
public enum FrontMatter {
    public static func render(
        title: String,
        source: String,
        pages: Int,
        converted: String,
        tool: String
    ) -> String {
        """
        ---
        title: \(quoted(title))
        source: \(quoted(source))
        pages: \(pages)
        converted: \(quoted(converted))
        tool: \(quoted(tool))
        ---
        """
    }

    private static func quoted(_ value: String) -> String {
        var output = "\""
        for character in value {
            switch character {
            case "\\": output += "\\\\"
            case "\"": output += "\\\""
            case "\n", "\r", "\t": output += " "
            default: output.append(character)
            }
        }
        return output + "\""
    }
}

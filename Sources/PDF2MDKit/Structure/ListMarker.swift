/// Recognizes the marker at the start of a list item.
public enum ListMarker {
    /// Bullet glyphs, including the private-use code points Symbol and Wingdings map to.
    private static let bullets: Set<Character> = [
        "•", "◦", "▪", "▫", "‣", "⁃", "∙", "·", "●", "○", "■", "□", "◆", "◇", "▶", "►", "➢", "✓",
        "–",
        "—", "-", "*", "\u{F0B7}", "\u{F0A7}", "\u{F0D8}", "\u{F0FC}", "\u{F076}", "\u{F0E0}",
        "\u{F0A8}", "\u{F06E}", "\u{F071}", "\u{F075}", "\u{F0B0}", "\u{F02D}",
    ]

    /// Bullet glyphs that can't start ordinary text, so they count even when attached to a word.
    private static let attachableBullets = bullets.subtracting(["–", "—", "-", "*", "·"])

    public static func isBullet(_ character: Character) -> Bool {
        bullets.contains(character)
    }

    /// The Markdown marker for a first word, when that word is only a marker.
    public static func marker(forToken token: String) -> String? {
        if token.count == 1, let character = token.first, bullets.contains(character) {
            return "-"
        }
        if let match = token.wholeMatch(of: /\(?(\d{1,3})[.)]/) {
            let opensParenthesis = token.hasPrefix("(")
            if opensParenthesis, !token.hasSuffix(")") { return nil }
            return "\(match.1)."
        }
        if token.wholeMatch(of: /\(?[a-z]\)|[a-z]\./) != nil { return "-" }
        if token.wholeMatch(of: /\(?(i{1,3}|iv|v|vi{1,3}|ix|x)\)/) != nil { return "-" }
        return nil
    }

    /// Splits `•text`, where the bullet is attached to its first word.
    public static func attachedBullet(in token: String) -> String? {
        guard token.count > 1, let first = token.first, attachableBullets.contains(first) else {
            return nil
        }
        return String(token.dropFirst())
    }
}

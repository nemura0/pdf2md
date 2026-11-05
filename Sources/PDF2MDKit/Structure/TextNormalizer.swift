import Foundation

/// Cleans PDF text: ligatures, the spacing accents pdfTeX emits, NFC.
public enum TextNormalizer {
    private static let ligatures: [Character: String] = [
        "ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl", "ﬅ": "st", "ﬆ": "st",
    ]

    /// OT1 pdfTeX draws an accent glyph before its letter, so `á` extracts as `´a`. Only the
    /// letters each accent really goes on are combined, which leaves `it´s` alone.
    private static let spacingAccents:
        [Character: (combining: Character, letters: Set<Character>)] = [
            "´": ("\u{301}", Set("aeiouyAEIOUYı")),
            "`": ("\u{300}", Set("aeiouAEIOUı")),
            "¨": ("\u{308}", Set("aeiouyAEIOUYı")),
            "˜": ("\u{303}", Set("anoANO")),
            "ˆ": ("\u{302}", Set("aeiouAEIOUı")),
            "¸": ("\u{327}", Set("cC")),
        ]

    public static func normalize(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var pendingAccent: Character?
        for character in text {
            if let accent = pendingAccent {
                pendingAccent = nil
                if let mapping = spacingAccents[accent], mapping.letters.contains(character) {
                    output.append(character == "ı" ? "i" : character)
                    output.append(mapping.combining)
                    continue
                }
                output.append(accent)
            }
            if spacingAccents[character] != nil {
                pendingAccent = character
            } else if let ligature = ligatures[character] {
                output += ligature
            } else if character == "\u{A0}" {
                output.append(" ")
            } else if character != "\u{AD}" {
                output.append(character)
            }
        }
        if let pendingAccent { output.append(pendingAccent) }
        return output.precomposedStringWithCanonicalMapping
    }
}

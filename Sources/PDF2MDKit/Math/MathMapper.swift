/// Maps math characters to LaTeX, for fonts and characters the span detector has flagged.
public enum MathMapper {
    private static let commands: [Character: String] = {
        var table: [Character: String] = [:]
        let groups: [String: [(Character, String)]] = [
            "lower greek": [
                ("α", "alpha"), ("β", "beta"), ("γ", "gamma"), ("δ", "delta"), ("ε", "varepsilon"),
                ("ϵ", "epsilon"), ("ζ", "zeta"), ("η", "eta"), ("θ", "theta"), ("ϑ", "vartheta"),
                ("ι", "iota"), ("κ", "kappa"), ("ϰ", "varkappa"), ("λ", "lambda"), ("μ", "mu"),
                ("µ", "mu"), ("ν", "nu"),
                ("ξ", "xi"), ("π", "pi"), ("ϖ", "varpi"), ("ρ", "rho"), ("ϱ", "varrho"),
                ("σ", "sigma"), ("ς", "varsigma"), ("τ", "tau"), ("υ", "upsilon"), ("φ", "varphi"),
                ("ϕ", "phi"), ("χ", "chi"), ("ψ", "psi"), ("ω", "omega"),
            ],
            "upper greek": [
                ("Γ", "Gamma"), ("Δ", "Delta"), ("Θ", "Theta"), ("Λ", "Lambda"), ("Ξ", "Xi"),
                ("Π", "Pi"), ("Σ", "Sigma"), ("Υ", "Upsilon"), ("Φ", "Phi"), ("Ψ", "Psi"),
                ("Ω", "Omega"), ("ϴ", "Theta"),
            ],
            "operators": [
                ("∑", "sum"), ("∏", "prod"), ("∐", "coprod"), ("∫", "int"), ("∮", "oint"),
                ("⋂", "bigcap"), ("⋃", "bigcup"), ("±", "pm"), ("∓", "mp"), ("×", "times"),
                ("÷", "div"), ("⋅", "cdot"), ("·", "cdot"), ("∘", "circ"), ("∗", "ast"),
                ("⊕", "oplus"), ("⊗", "otimes"), ("∧", "land"), ("∨", "lor"), ("¬", "neg"),
                ("∩", "cap"), ("∪", "cup"), ("∖", "setminus"), ("∇", "nabla"), ("∂", "partial"),
            ],
            "relations": [
                ("≤", "leq"), ("≥", "geq"), ("≠", "neq"), ("≈", "approx"), ("≡", "equiv"),
                ("∼", "sim"), ("≃", "simeq"), ("≅", "cong"), ("∝", "propto"), ("≪", "ll"),
                ("≫", "gg"), ("∈", "in"), ("∉", "notin"), ("∋", "ni"), ("⊂", "subset"),
                ("⊃", "supset"), ("⊆", "subseteq"), ("⊇", "supseteq"), ("⊥", "perp"), ("∣", "mid"),
                ("∥", "parallel"), ("≺", "prec"), ("≻", "succ"), ("⊢", "vdash"), ("⊨", "models"),
            ],
            "arrows": [
                ("→", "to"), ("←", "leftarrow"), ("↔", "leftrightarrow"), ("⇒", "Rightarrow"),
                ("⇐", "Leftarrow"), ("⇔", "Leftrightarrow"), ("↦", "mapsto"), ("↑", "uparrow"),
                ("↓", "downarrow"),
            ],
            "misc": [
                ("∞", "infty"), ("∅", "emptyset"), ("∀", "forall"), ("∃", "exists"),
                ("∄", "nexists"),
                ("ℵ", "aleph"), ("ℓ", "ell"), ("ℏ", "hbar"), ("ℜ", "Re"), ("ℑ", "Im"),
                ("…", "ldots"),
                ("⋯", "cdots"), ("⟨", "langle"), ("⟩", "rangle"), ("⌊", "lfloor"), ("⌋", "rfloor"),
                ("⌈", "lceil"), ("⌉", "rceil"), ("∴", "therefore"), ("∵", "because"), ("°", "circ"),
            ],
        ]
        for group in groups.values {
            for (symbol, name) in group { table[symbol] = "\\" + name }
        }
        // Greek capitals drawn like Latin ones have no LaTeX command.
        for (greek, latin) in zip("ΑΒΕΖΗΙΚΜΝΟΡΤΧο", "ABEZHIKMNOPTXo") {
            table[greek] = String(latin)
        }
        table["√"] = "\\sqrt{}"
        table["ℝ"] = "\\mathbb{R}"
        table["ℕ"] = "\\mathbb{N}"
        table["ℤ"] = "\\mathbb{Z}"
        table["ℚ"] = "\\mathbb{Q}"
        table["ℂ"] = "\\mathbb{C}"
        table["−"] = "-"
        table["′"] = "'"
        table["″"] = "''"
        table["∶"] = ":"
        return table
    }()

    private static let escaped: Set<Character> = ["%", "_", "{", "}", "&", "#", "$"]
    private static let mathLetterOffsets = mathLetterRanges()
    /// The Planck constant sits outside the math italic block, where its letter would be.
    private static let planckConstant = UnicodeScalar(0x210E)

    public static func hasCommand(_ character: Character) -> Bool {
        commands[character] != nil
    }

    /// LaTeX for a run of characters, with a space only where a command would swallow a letter.
    public static func latex(for text: String) -> String {
        var output = ""
        for character in text {
            let piece = latex(forCharacter: character)
            if output.last.map({ $0.isLetter }) == true, piece.first?.isLetter == true,
                endsInCommand(output)
            {
                output += " "
            }
            output += piece
        }
        return output
    }

    private static func latex(forCharacter character: Character) -> String {
        if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
            let plain = plainCharacter(for: scalar)
        {
            return commands[plain] ?? String(plain)
        }
        if let command = commands[character] { return command }
        if character == "<" { return #"\lt"# }  // A bare `<` can read as an HTML tag (A11).
        return escaped.contains(character) ? "\\\(character)" : String(character)
    }

    /// Whether the text ends in a `\command`, which a following letter would run into.
    static func endsInCommand(_ text: String) -> Bool {
        var seenLetter = false
        for character in text.reversed() {
            if character.isLetter, character.isASCII {
                seenLetter = true
                continue
            }
            return character == "\\" && seenLetter
        }
        return false
    }

    /// The letter, digit or Greek letter behind a Mathematical Alphanumeric Symbol, whatever its
    /// style. Math italic carries no meaning here, and plain letters cost fewer tokens.
    static func plainCharacter(for scalar: UnicodeScalar) -> Character? {
        if scalar == planckConstant { return "h" }
        for range in mathLetterOffsets where range.scalars.contains(scalar.value) {
            let offset = (scalar.value - range.scalars.lowerBound) % range.cycle
            return range.characters[Int(offset)]
        }
        return nil
    }

    private struct LetterRange {
        let scalars: ClosedRange<UInt32>
        let cycle: UInt32
        let characters: [Character]
    }

    private static func mathLetterRanges() -> [LetterRange] {
        let latin = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let upperGreek = Array("ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡϴΣΤΥΦΧΨΩ∇")
        let lowerGreek = Array("αβγδεζηθικλμνξοπρςστυφχψω∂ϵϑϰϕϱϖ")
        return [
            LetterRange(scalars: 0x1D400...0x1D6A3, cycle: 52, characters: latin),
            LetterRange(
                // The two after this are bold digamma, which has no place in this table.
                scalars: 0x1D6A8...0x1D7C9,
                cycle: 58,
                characters: upperGreek + lowerGreek
            ),
            LetterRange(scalars: 0x1D7CE...0x1D7FF, cycle: 10, characters: Array("0123456789")),
        ]
    }
}

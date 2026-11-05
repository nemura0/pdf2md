import CoreGraphics
import Testing

@testable import PDF2MDKit

extension FontStyle {
    static let mathItalic = FontStyle(
        name: "CMMI10",
        isBold: false,
        isItalic: true,
        isMonospace: false
    )
    static let mathSymbol = FontStyle(
        name: "CMSY10",
        isBold: false,
        isItalic: false,
        isMonospace: false
    )
}

@Suite("MathMapper")
struct MathMapperTests {
    @Test(
        "symbols become LaTeX commands",
        arguments: [
            ("α", "\\alpha"), ("Γ", "\\Gamma"), ("∑", "\\sum"), ("≤", "\\leq"), ("≥", "\\geq"),
            ("≠", "\\neq"), ("∅", "\\emptyset"), ("⇒", "\\Rightarrow"), ("∞", "\\infty"),
            ("∈", "\\in"), ("×", "\\times"), ("→", "\\to"), ("∫", "\\int"), ("√", "\\sqrt{}"),
        ]
    )
    func symbols(symbol: String, latex: String) {
        #expect(MathMapper.latex(for: symbol) == latex)
    }

    @Test(
        "math alphanumerics become plain letters",
        arguments: [("𝑛", "n"), ("𝐴", "A"), ("𝛼", "\\alpha"), ("𝟏", "1"), ("𝒙", "x"), ("ℎ", "h")]
    )
    func alphanumerics(symbol: String, latex: String) {
        #expect(MathMapper.latex(for: symbol) == latex)
    }

    @Test("commands are separated from letters, and not from symbols")
    func spacing() {
        #expect(MathMapper.latex(for: "αx") == "\\alpha x")
        #expect(MathMapper.latex(for: "α+β") == "\\alpha+\\beta")
        #expect(MathMapper.latex(for: "∑i") == "\\sum i")
    }

    @Test("characters special to LaTeX are escaped")
    func specials() {
        #expect(MathMapper.latex(for: "50%") == "50\\%")
        #expect(MathMapper.latex(for: "a_b") == "a\\_b")
        #expect(MathMapper.latex(for: "{x}") == "\\{x\\}")
        #expect(MathMapper.latex(for: "a&b") == "a\\&b")
    }

    @Test("the minus sign and primes come out plain")
    func plain() {
        #expect(MathMapper.latex(for: "2n−1") == "2n-1")
        #expect(MathMapper.latex(for: "x′") == "x'")
    }
}

@Suite("MathSpans")
struct MathSpanTests {
    private func mathWord(_ text: String, x: Double, y: Double = 100, size: Double = 10) -> Word {
        word(text, x: x, y: y, size: size, font: .mathItalic)
    }

    @Test("math fonts count, and so do math characters in any font")
    func detection() {
        #expect(MathSpans.isMath(word("x", x: 0, y: 0, font: .mathItalic)))
        #expect(MathSpans.isMath(word("≤", x: 0, y: 0)))
        #expect(MathSpans.isMath(word("𝑥", x: 0, y: 0)))
        #expect(MathSpans.isMath(word("β", x: 0, y: 0)))
        #expect(!MathSpans.isMath(word("hello", x: 0, y: 0)))
        #expect(!MathSpans.isMath(word("=", x: 0, y: 0)))
    }

    @Test(
        "font names that mean math",
        arguments: [
            "CMMI10", "CMSY7", "CMEX10", "MSBM10", "MSAM10", "STIXTwoMath-Regular",
            "CambriaMath", "LatinModernMath-Regular", "XITSMath",
        ]
    )
    func mathFonts(name: String) {
        #expect(MathSpans.isMathFont(name))
    }

    @Test(
        "ordinary fonts aren't math",
        arguments: ["Times-Roman", "CMR10", "Helvetica", "Mathilde", "STIXGeneral-Regular"]
    )
    func textFonts(name: String) {
        #expect(!MathSpans.isMathFont(name))
    }

    @Test("STIX counts for short italic variables, not for its running text")
    func stixText() {
        let italic = FontStyle(
            name: "STIXGeneral-Italic",
            isBold: false,
            isItalic: true,
            isMonospace: false
        )
        #expect(MathSpans.isMath(word("x", x: 0, y: 0, font: italic)))
        #expect(!MathSpans.isMath(word("however", x: 0, y: 0, font: italic)))
    }

    @Test("connectors join two math words but a trailing period stays outside")
    func spans() {
        let words =
            [word("Let", x: 72, y: 100)] + [
                mathWord("x", x: 95),
                word("=", x: 105, y: 100),
                word("2", x: 115, y: 100),
                word("+", x: 125, y: 100),
                mathWord("y", x: 135),
                word("hold.", x: 150, y: 100),
            ]
        let text = MathSpans.render(words, baseline: 100, size: 10)
        #expect(text == "Let $x = 2 + y$ hold.")
    }

    @Test("a word in plain text with no math around it is untouched")
    func plain() {
        let words = [word("a", x: 72, y: 100), word("=", x: 82, y: 100), word("b", x: 92, y: 100)]
        #expect(MathSpans.render(words, baseline: 100, size: 10) == nil)
    }

    @Test("smaller raised text is a superscript and smaller lowered text a subscript")
    func scripts() {
        let raised = [
            mathWord("x", x: 72),
            Word(
                text: "2",
                rect: CGRect(x: 77, y: 92, width: 4, height: 7),
                baseline: 96,
                size: 7,
                font: .mathItalic,
                isGlued: true
            ),
        ]
        #expect(MathSpans.render(raised, baseline: 100, size: 10) == "$x^2$")

        let lowered = [
            mathWord("T", x: 72),
            Word(
                text: "ij",
                rect: CGRect(x: 77, y: 98, width: 6, height: 7),
                baseline: 103,
                size: 7,
                font: .mathItalic,
                isGlued: true
            ),
        ]
        #expect(MathSpans.render(lowered, baseline: 100, size: 10) == "$T_{ij}$")
    }

    @Test("text sized like the line stays on the line")
    func noScript() {
        let words = [
            mathWord("x", x: 72),
            mathWord("y", x: 80).withGlue(),
        ]
        #expect(MathSpans.render(words, baseline: 100, size: 10) == "$xy$")
    }

    @Test("a whole line of math is display math, and a sentence with a formula isn't")
    func display() {
        let formula = [
            mathWord("x", x: 200),
            word("=", x: 212, y: 100),
            mathWord("y", x: 224),
            word("+", x: 236, y: 100),
            word("1", x: 248, y: 100),
        ]
        #expect(MathSpans.displayLatex(TextLine(words: formula)) == "x = y + 1")

        let sentence = [word("Let", x: 72, y: 100), mathWord("x", x: 95)]
        #expect(MathSpans.displayLatex(TextLine(words: sentence)) == nil)
    }

    @Test("a lone symbol isn't display math")
    func loneSymbol() {
        #expect(MathSpans.displayLatex(TextLine(words: [mathWord("x", x: 200)])) == nil)
    }
}

extension Word {
    fileprivate func withGlue() -> Word {
        var copy = self
        copy.isGlued = true
        return copy
    }
}

@Suite("StackedEquations")
struct StackedEquationTests {
    private func mathLine(_ text: String, x: Double, y: Double) -> TextLine {
        line(text, x: x, y: y, font: .mathItalic)
    }

    @Test("lines of math set close together form one stacked equation, with a linear form")
    func fraction() throws {
        let lines = [
            line("Plain words before the equation sit on a line above it.", y: 60),
            mathLine("n + 1", x: 212, y: 92),
            mathLine("R =", x: 190, y: 100),
            mathLine("2n - 1", x: 212, y: 109),
            line("Plain words after the equation sit on a line below it.", y: 140),
        ]
        let clusters = StackedEquations.find(in: lines, rules: [])
        #expect(clusters.count == 1)
        let cluster = try #require(clusters.first)
        #expect(cluster.lines.count == 3)
        #expect(cluster.linearLatex == "R = n + 1 / 2n - 1")
    }

    @Test("two display equations with a normal gap are separate, not stacked")
    func separateEquations() {
        let lines = [
            mathLine("x = 1", x: 200, y: 100),
            mathLine("y = 2", x: 200, y: 124),
        ]
        #expect(StackedEquations.find(in: lines, rules: []).isEmpty)
    }

    @Test("a fraction rule between two math lines makes them a stack")
    func fractionRule() {
        let lines = [mathLine("a", x: 200, y: 100), mathLine("b", x: 200, y: 112)]
        let rule = RuleSegment(startX: 198, startY: 104, endX: 212, endY: 104)
        #expect(StackedEquations.find(in: lines, rules: [rule]).count == 1)
    }

    @Test("ordinary text lines are never a stack")
    func textLines() {
        let lines = [
            line("Some words on one line", y: 100),
            line("Some words on the next", y: 112),
        ]
        #expect(StackedEquations.find(in: lines, rules: []).isEmpty)
    }
}

@Suite("Math in blocks")
struct MathBlockTests {
    private let profile = DocumentProfile(
        pageCount: 1,
        bodySize: 10,
        headingBands: [],
        title: DocumentTitle(text: "T", lineTexts: []),
        repeatedMarginKeys: [],
        repeatedImageDigests: [],
        isSlideDeck: false
    )
    private let cmmi = FontStyle(name: "CMMI10", isBold: false, isItalic: true, isMonospace: false)

    @Test("a whole line of math is a display block, and it ends the paragraph before it")
    func display() {
        let equation = TextLine(words: words("x = y", y: 120, font: cmmi))
        let blocks = BlockBuilder(profile: profile).blocks(
            from: [line("Some text before it", y: 100), equation],
            isSlidePage: false
        )
        #expect(blocks == [.paragraph("Some text before it"), .displayMath("x = y")])
    }

    @Test("math inside a sentence is inline, and list items get it too")
    func inline() {
        let sentence = TextLine(
            words: words("Let", y: 100) + words("x", x: 100, y: 100, font: cmmi)
                + words("hold", x: 120, y: 100)
        )
        let blocks = BlockBuilder(profile: profile).blocks(
            from: [sentence],
            isSlidePage: false
        )
        #expect(blocks == [.paragraph("Let $x$ hold")])

        let item = TextLine(
            words: words("-", y: 100) + words("Take", x: 90, y: 100)
                + words("y", x: 120, y: 100, font: cmmi)
        )
        let list = BlockBuilder(profile: profile).blocks(from: [item], isSlidePage: false)
        #expect(list == [.list([ListItem(depth: 0, marker: "-", text: "Take $y$")])])
    }

    @Test("a monospace line is never math, whatever its symbols")
    func code() {
        let code = TextLine(words: words("α = 1", y: 100, font: .mono))
        let blocks = BlockBuilder(profile: profile).blocks(from: [code], isSlidePage: false)
        #expect(blocks == [.code(["α = 1"])])
    }

    @Test("formulas are counted, and an escaped dollar isn't one")
    func count() {
        let blocks: [Block] = [
            .paragraph("Cost \\$5 for $x$ and $y$"),
            .displayMath("z"),
            .list([ListItem(depth: 0, marker: "-", text: "$w$")]),
            .code(["$not$"]),
        ]
        #expect(MathSpans.count(in: blocks) == 4)
    }
}

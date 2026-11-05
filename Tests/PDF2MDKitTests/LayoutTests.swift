import CoreGraphics
import Testing

@testable import PDF2MDKit

@Suite("LineBuilder")
struct LineBuilderTests {
    @Test("words on one baseline form one line, in x order")
    func simpleLine() {
        let input = [word("world", x: 110, y: 100), word("Hello", x: 72, y: 100)]
        let lines = LineBuilder.lines(from: input)
        #expect(lines.map(\.text) == ["Hello world"])
    }

    @Test("lines come back top to bottom")
    func topToBottom() {
        let input = words("second", y: 114) + words("first", y: 100)
        #expect(LineBuilder.lines(from: input).map(\.text) == ["first", "second"])
    }

    @Test("two columns on one baseline split at the gutter")
    func twoColumnsSplit() {
        let input = words("left text", x: 72, y: 100) + words("right text", x: 320, y: 100)
        #expect(LineBuilder.lines(from: input).map(\.text) == ["left text", "right text"])
    }

    @Test("a superscript stays on its line and keeps its own baseline")
    func superscript() {
        let input = [
            word("x", x: 72, y: 100),
            word("2", x: 77, y: 96, size: 7, isGlued: true),
            word("grows", x: 85, y: 100),
        ]
        let lines = LineBuilder.lines(from: input)
        #expect(lines.map(\.text) == ["x2 grows"])
        #expect(lines[0].baseline == 100)
        #expect(lines[0].size == 10)
    }

    @Test("a small line number stays with its code, however deep the indentation")
    func lineNumberStaysWithCode() throws {
        let input = [
            word("3", x: 15, y: 100, size: 5),
            word("public", x: 61, y: 100, size: 8, font: .mono),
            word("static", x: 94, y: 100, size: 8, font: .mono),
        ]
        let line = try #require(LineBuilder.lines(from: input).first)
        #expect(LineBuilder.lines(from: input).count == 1)
        #expect(line.isMonospace)
        #expect(line.lineNumber?.text == "3")
        #expect(line.size == 8)
    }

    @Test("one digit and one brace is still a line of code")
    func lineNumberAndBrace() throws {
        let input = [
            word("2", x: 15, y: 100, size: 5),
            word("{", x: 23, y: 100, size: 8, font: .mono),
        ]
        let line = try #require(LineBuilder.lines(from: input).first)
        #expect(line.isMonospace)
    }

    @Test("a footnote marker against a URL isn't a line number")
    func footnoteMarkerIsNotALineNumber() throws {
        let marker = word("2", x: 72, y: 100, size: 5)
        let url = word("https://example.org/", x: marker.rect.maxX + 0.5, y: 100, size: 8, font: .mono)
        let line = try #require(LineBuilder.lines(from: [marker, url]).first)
        #expect(line.lineNumber == nil)
    }

    @Test("a number at text size before prose isn't a line number")
    func numberBeforeProse() throws {
        let line = try #require(LineBuilder.lines(from: words("4 veces", y: 100)).first)
        #expect(line.lineNumber == nil)
    }

    @Test("a stacked numerator is not merged with the line below")
    func stackedLinesStaySeparate() {
        let input = words("numerator", x: 200, y: 92) + words("denominator", x: 200, y: 109)
        #expect(LineBuilder.lines(from: input).count == 2)
    }

    @Test("a wide gap between monospace words is alignment, not a column")
    func monospaceGapStays() {
        let input =
            words("int x;", x: 72, y: 100, font: .mono)
            + words("// comment", x: 250, y: 100, font: .mono)
        #expect(LineBuilder.lines(from: input).count == 1)
    }

    @Test("a word drawn twice for fake bold appears once")
    func fakeBold() {
        let input = [word("Title", x: 72, y: 100), word("Title", x: 72.3, y: 100)]
        #expect(LineBuilder.lines(from: input).map(\.text) == ["Title"])
    }

    @Test("empty input gives no lines")
    func empty() {
        #expect(LineBuilder.lines(from: []).isEmpty)
    }
}

@Suite("ReadingOrder")
struct ReadingOrderTests {
    private func column(_ prefix: String, x: Double, from y: Double, count: Int) -> [TextLine] {
        (0..<count).map { index in
            line(
                "\(prefix)\(index) some words that fill a column line",
                x: x,
                y: y + Double(index) * 14
            )
        }
    }

    @Test("a single column stays top to bottom")
    func singleColumn() {
        let lines = column("a", x: 72, from: 100, count: 6)
        let ordered = ReadingOrder.order(lines.reversed())
        #expect(ordered.map(\.text) == lines.map(\.text))
    }

    @Test("two columns on shared baselines read left then right")
    func twoColumns() {
        let left = column("L", x: 72, from: 100, count: 6)
        let right = column("R", x: 330, from: 100, count: 6)
        let ordered = ReadingOrder.order((left + right).shuffled())
        #expect(ordered.map(\.text) == (left + right).map(\.text))
    }

    @Test("full-width lines above and below separate the column band")
    func spanningLines() {
        let wide = String(repeating: "wide words ", count: 10)
        let heading = line(wide + "top", x: 72, y: 80)
        let left = column("L", x: 72, from: 100, count: 5)
        let right = column("R", x: 330, from: 100, count: 5)
        let footer = line(wide + "bottom", x: 72, y: 200)
        let ordered = ReadingOrder.order((right + [footer] + left + [heading]).shuffled())
        let expected = [heading] + left + right + [footer]
        #expect(ordered.map(\.text) == expected.map(\.text))
    }

    @Test("short lines at the side don't make a column")
    func notColumns() {
        let lines = [
            line("Name: value", x: 72, y: 100),
            line("Other", x: 330, y: 140),
            line("Name: value two", x: 72, y: 180),
        ]
        let ordered = ReadingOrder.order(lines)
        #expect(ordered.map(\.text) == lines.map(\.text))
    }
}

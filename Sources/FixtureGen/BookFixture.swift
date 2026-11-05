import CoreGraphics
import Foundation

/// A piece of inline text, set in text or math fonts, for lines mixing the two.
enum InlineRun {
    case text(String)
    case math(String)
    case superscript(String)
    case `subscript`(String)
}

/// Lays out a book-like document page by page and records what it drew.
final class BookWriter {
    let canvas: PDFCanvas
    var truth = GroundTruth()
    private let runningTitle: String
    private var y: CGFloat = 0
    private var isPageOpen = false

    private let left: CGFloat = 72
    private let right: CGFloat = 540
    private let top: CGFloat = 712
    private let bottom: CGFloat = 76
    private let bodySize: CGFloat = 10.5
    private let leading: CGFloat = 14

    init(title: String, runningTitle: String) throws {
        canvas = try PDFCanvas(
            pageSize: CGSize(width: 612, height: 792),
            title: title,
            extraInfo: [kCGPDFContextAuthor: "pdf2md fixtures"]
        )
        self.runningTitle = runningTitle
        truth.title = title
    }

    // MARK: Pages

    func titlePage(title: String, subtitle: String, author: String) {
        canvas.beginPage()
        isPageOpen = true
        canvas.text(title, font: .sansBold, size: 26, x: left, y: 560)
        canvas.text(subtitle, font: .sans, size: 14, x: left, y: 530)
        canvas.text(author, font: .sans, size: 11, x: left, y: 505)
        truth.words += words(in: subtitle) + words(in: author)
        closePage()
    }

    func newPage() {
        closePage()
        canvas.beginPage()
        isPageOpen = true
        y = top
        drawMargins(page: canvas.pageCount)
    }

    func finish(label: String) -> Data {
        closePage()
        truth.pageCount = canvas.pageCount
        return canvas.finish(label: label)
    }

    private func closePage() {
        guard isPageOpen else { return }
        canvas.endPage()
        isPageOpen = false
    }

    /// Running header with the number on alternating sides, and a footer. Digits differ on
    /// every page, which is what the margin filter's normalization has to handle.
    private func drawMargins(page: Int) {
        let header =
            page.isMultiple(of: 2) ? "\(page)   \(runningTitle)" : "\(runningTitle)   \(page)"
        canvas.text(header, font: .bodyItalic, size: 9, x: left, y: 750)
        let footer = "Draft edition, page \(page)"
        canvas.text(footer, font: .body, size: 8, x: left, y: 40)
        truth.forbiddenLines += [header, footer]
    }

    private func ensureRoom(_ height: CGFloat) {
        if !isPageOpen || y - height < bottom { newPage() }
    }

    // MARK: Blocks

    func heading(level: Int, _ text: String) {
        let size: CGFloat = [2: 17, 3: 13.5, 4: 11.5][level] ?? bodySize
        let font: FixtureFont = level == 4 ? .bodyBold : .sansBold
        ensureRoom(size * 3)
        y -= size * 0.9
        canvas.text(text, font: font, size: size, x: left, y: y)
        y -= size * 0.9
        truth.headings.append(.init(level: level, text: text))
    }

    func paragraph(_ text: String) {
        let lines = wrap(text, font: .body, size: bodySize, width: right - left)
        ensureRoom(leading * 2)
        for (index, line) in lines.enumerated() {
            ensureRoom(leading)
            canvas.text(line, font: .body, size: bodySize, x: left, y: y)
            y -= leading
            _ = index
        }
        y -= leading * 0.5
        truth.words += words(in: text)
    }

    /// A paragraph with explicit line breaks, for testing hyphen joins. `joined` is what a
    /// correct reflow produces.
    func lines(_ lines: [String], joined: String) {
        ensureRoom(leading * CGFloat(lines.count))
        for line in lines {
            canvas.text(line, font: .body, size: bodySize, x: left, y: y)
            y -= leading
        }
        y -= leading * 0.5
        truth.words += words(in: joined)
    }

    func list(_ items: [(depth: Int, marker: String, text: String)]) {
        for item in items {
            let markerX = left + 14 + CGFloat(item.depth) * 18
            let textX = markerX + 14
            let lines = wrap(item.text, font: .body, size: bodySize, width: right - textX)
            ensureRoom(leading * CGFloat(lines.count))
            canvas.text(item.marker, font: .body, size: bodySize, x: markerX, y: y)
            for line in lines {
                canvas.text(line, font: .body, size: bodySize, x: textX, y: y)
                y -= leading
            }
            truth.words += words(in: item.text)
        }
        y -= leading * 0.5
    }

    func code(_ lines: [String]) {
        let size: CGFloat = 9
        ensureRoom(CGFloat(lines.count) * 12 + 8)
        for line in lines {
            canvas.text(line, font: .mono, size: size, x: left + 10, y: y)
            y -= 12
        }
        y -= 8
        truth.codeLines += lines
    }

    func table(_ rows: [[String]], columnWidths: [CGFloat]) {
        let rowHeight: CGFloat = 20
        let height = CGFloat(rows.count) * rowHeight
        ensureRoom(height + 16)
        let width = columnWidths.reduce(0, +)
        let tableTop = y
        for row in 0...rows.count {
            let lineY = tableTop - CGFloat(row) * rowHeight
            canvas.rule(from: CGPoint(x: left, y: lineY), to: CGPoint(x: left + width, y: lineY))
        }
        var columnX = left
        for columnWidth in columnWidths + [0] {
            canvas.rule(
                from: CGPoint(x: columnX, y: tableTop),
                to: CGPoint(x: columnX, y: tableTop - height)
            )
            columnX += columnWidth
        }
        for (rowIndex, row) in rows.enumerated() {
            var cellX = left
            for (columnIndex, cell) in row.enumerated() {
                let baseline = tableTop - CGFloat(rowIndex) * rowHeight - 14
                let font: FixtureFont = rowIndex == 0 ? .bodyBold : .body
                canvas.text(cell, font: font, size: 10, x: cellX + 5, y: baseline)
                cellX += columnWidths[columnIndex]
            }
        }
        y = tableTop - height - 14
        truth.tables.append(rows)
    }

    /// A line mixing text and math, with sub and superscripts as real size and baseline shifts.
    func inlineMath(_ runs: [InlineRun], fragments: [String]) {
        ensureRoom(leading * 2)
        drawRuns(runs, startX: left)
        y -= leading * 1.3
        for case .text(let text) in runs { truth.words += words(in: text) }
        truth.mathFragments += fragments
    }

    /// A centered display equation on one line, which the math stage can rebuild.
    func displayMath(_ runs: [InlineRun], fragments: [String]) {
        ensureRoom(leading * 3)
        y -= leading * 0.5
        drawRuns(runs, startX: left + 130)
        y -= leading * 1.6
        truth.mathFragments += fragments
    }

    /// `numerator / denominator` stacked with a rule, plus a prefix. It can't be rebuilt
    /// confidently, so it must come out as a linearization plus a crop.
    func stackedFraction(prefix: String, numerator: String, denominator: String) {
        ensureRoom(leading * 5)
        y -= leading
        let x = left + 150
        let baseline = y
        let prefixWidth = canvas.text(prefix, font: .math, size: bodySize, x: x, y: baseline)
        let fractionX = x + prefixWidth + 4
        let width =
            max(
                canvas.width(of: numerator, font: .math, size: bodySize),
                canvas.width(of: denominator, font: .math, size: bodySize)
            ) + 4
        canvas.text(numerator, font: .math, size: bodySize, x: fractionX + 2, y: baseline + 8)
        canvas.rule(
            from: CGPoint(x: fractionX, y: baseline + 3.5),
            to: CGPoint(x: fractionX + width, y: baseline + 3.5),
            width: 0.5
        )
        canvas.text(denominator, font: .math, size: bodySize, x: fractionX + 2, y: baseline - 9)
        y -= leading * 2.2
    }

    /// One column-spanning heading, then two columns of text.
    func twoColumnPage(heading text: String, left leftLines: [String], right rightLines: [String]) {
        newPage()
        heading(level: 3, text)
        let columnWidth: CGFloat = 220
        let gutter: CGFloat = 28
        let startY = y
        for (index, line) in leftLines.enumerated() {
            let lineY = startY - CGFloat(index) * leading
            canvas.text(line, font: .body, size: bodySize, x: left, y: lineY)
        }
        for (index, line) in rightLines.enumerated() {
            let lineY = startY - CGFloat(index) * leading
            let x = left + columnWidth + gutter
            canvas.text(line, font: .body, size: bodySize, x: x, y: lineY)
        }
        truth.words += (leftLines + rightLines).flatMap(words(in:))
        y = startY - CGFloat(max(leftLines.count, rightLines.count)) * leading - leading
    }

    private func drawRuns(_ runs: [InlineRun], startX: CGFloat) {
        var x = startX
        for run in runs {
            switch run {
            case .text(let text):
                x += canvas.text(text, font: .body, size: bodySize, x: x, y: y)
            case .math(let text):
                x += canvas.text(text, font: .math, size: bodySize, x: x, y: y)
            case .superscript(let text):
                x += canvas.text(text, font: .math, size: 7.5, x: x, y: y + 4)
            case .subscript(let text):
                x += canvas.text(text, font: .math, size: 7.5, x: x, y: y - 2.5)
            }
        }
    }

    private func wrap(
        _ text: String,
        font: FixtureFont,
        size: CGFloat,
        width: CGFloat
    ) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if canvas.width(of: candidate, font: font, size: size) > width, !current.isEmpty {
                lines.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private func words(in text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }
}

enum BookFixture {
    static let title = "Foundations of Computing"

    static func make() throws -> (data: Data, truth: GroundTruth) {
        let book = try BookWriter(title: title, runningTitle: title)
        book.titlePage(
            title: title,
            subtitle: "Lecture notes for a first course",
            author: "Prepared for the pdf2md test suite"
        )
        writeChapterOne(book)
        writeChapterTwo(book)
        writeChapterThree(book)
        writeChapterFour(book)
        let data = book.finish(label: "book")
        return (data, book.truth)
    }

    private static func writeChapterOne(_ book: BookWriter) {
        book.newPage()
        book.heading(level: 2, "Introduction")
        book.paragraph(
            """
            A computer is a machine that follows instructions without understanding them. This \
            course studies what such machines can do, how quickly they can do it, and how to \
            write programs that other people can read. The material assumes no previous \
            experience beyond basic algebra and a willingness to work through examples by hand.
            """
        )
        book.heading(level: 3, "Why study algorithms")
        book.paragraph(
            """
            Faster hardware does not rescue a poor method. Doubling the speed of a processor adds \
            very little when the running time of a program grows exponentially with its input, \
            while a better algorithm can turn an impossible task into a routine one. Learning to \
            reason about cost is therefore worth more than learning any particular language.
            """
        )
        book.lines(
            [
                "Careful analysis also prevents wasted effort, because it reveals where a program",
                "spends its time before anyone starts to optimize. Measuring first is a compre-",
                "hensive habit that pays for itself on every project, large or small.",
            ],
            joined: """
                Careful analysis also prevents wasted effort, because it reveals where a program \
                spends its time before anyone starts to optimize. Measuring first is a \
                comprehensive habit that pays for itself on every project, large or small.
                """
        )
        book.heading(level: 4, "A short history")
        book.paragraph(
            """
            Mechanical calculators came first, followed by programmable machines in the middle of \
            the twentieth century. Compilers then allowed people to write in notation closer to \
            mathematics, and that shift created the discipline this course belongs to.
            """
        )
        book.heading(level: 3, "What you will learn")
        book.list([
            (0, "•", "How to state a problem precisely before solving it."),
            (0, "•", "How to estimate cost using simple counting arguments."),
            (1, "◦", "Counting loop iterations in nested code."),
            (1, "◦", "Comparing growth rates of common functions."),
            (0, "•", "How to choose a data structure that fits the task."),
        ])
        book.paragraph("Each week follows the same routine, in this order:")
        book.list([
            (0, "1.", "Read the chapter before the lecture."),
            (0, "2.", "Solve the exercises marked as essential."),
            (0, "3.", "Discuss the remaining problems in the workshop."),
        ])
    }

    private static func writeChapterTwo(_ book: BookWriter) {
        book.newPage()
        book.heading(level: 2, "Measuring cost")
        book.paragraph(
            """
            To compare methods we count basic operations rather than seconds, since counts do not \
            depend on the machine. Growth rates describe how those counts change as the input \
            becomes larger, and they are what we compare when we choose between two algorithms.
            """
        )
        book.heading(level: 3, "Growth and notation")
        book.inlineMath(
            [
                .text("Let the input have size "), .math("𝑛"), .text(" and suppose "),
                .math("𝛼 ≤ 𝑥"), .superscript("2"), .text(" holds for every step "),
                .math("𝑥"), .subscript("𝑖"), .text("."),
            ],
            fragments: ["\\alpha", "\\leq", "x^{2}", "x_{i}"]
        )
        book.paragraph(
            """
            The next equation gives the cost of the outer loop, and the one after it shows the \
            closed form that we will derive in the workshop using a short induction argument.
            """
        )
        book.displayMath(
            [
                .math("𝑓(𝑥) = 𝛼𝑥"), .superscript("2"), .math(" + 𝛽𝑥 + 𝛾"),
            ],
            fragments: ["f(x)", "\\alpha", "x^{2}", "\\beta", "\\gamma"]
        )
        book.displayMath(
            [
                .math("𝑇"), .subscript("𝑛"), .math(" ≠ ∅ ⇒ ∑ 𝑖"), .superscript("2"),
                .math(" ≥ 0"),
            ],
            fragments: ["T_{n}", "\\neq", "\\emptyset", "\\Rightarrow", "\\sum", "\\geq"]
        )
        book.stackedFraction(prefix: "𝑅 =", numerator: "𝑛 + 1", denominator: "2𝑛 − 1")
        book.paragraph(
            """
            When a formula has a stacked fraction, a linear form can lose its structure, so the \
            page keeps an image of the equation next to the best linear form available.
            """
        )
        book.heading(level: 3, "Common costs")
        book.paragraph("The following table lists the cost of common operations on two structures.")
        book.table(
            [
                ["Operation", "Array", "Linked list"],
                ["Read by index", "constant", "linear"],
                ["Insert at front", "linear", "constant"],
                ["Search unsorted", "linear", "linear"],
            ],
            columnWidths: [160, 110, 110]
        )
        book.paragraph(
            """
            No structure wins on every operation, which is why choosing one starts by listing \
            what the program does most often.
            """
        )
    }

    private static func writeChapterThree(_ book: BookWriter) {
        book.newPage()
        book.heading(level: 2, "Programming in Java")
        book.paragraph(
            """
            Java organizes code into classes, and each class describes the state and behaviour of \
            its objects. The following example shows a small class with one field, a constructor \
            and a method that reads the field back.
            """
        )
        book.code([
            "public class Counter {",
            "    private int value;",
            "",
            "    public Counter(int start) {",
            "        this.value = start;",
            "    }",
            "",
            "    public int next() {",
            "        for (int i = 0; i < 2; i++) {",
            "            value += i;",
            "        }",
            "        return value;",
            "    }",
            "}",
        ])
        book.paragraph(
            """
            The field is private, so other classes can only change the count by calling a method. \
            Restricting access in this way lets the class keep its own rules true at all times.
            """
        )
        book.heading(level: 3, "Reading the example")
        book.list([
            (0, "•", "The constructor runs once when the object is created."),
            (0, "•", "The method updates the state and returns the new value."),
        ])
        book.heading(level: 4, "Exercises")
        book.list([
            (0, "1.", "Add a method that resets the counter to its starting value."),
            (0, "2.", "Explain why the field is not declared public."),
        ])
        book.paragraph(
            """
            Write your answers in plain language first and then translate them into code. Being \
            able to explain a program is the most reliable sign that you understand it well.
            """
        )
    }

    private static func writeChapterFour(_ book: BookWriter) {
        book.twoColumnPage(
            heading: "Reading in two columns",
            left: [
                "The left column begins here with a",
                "sentence that continues across several",
                "short lines so reading order matters a",
                "great deal for the final output, and",
                "the left column ends right here.",
            ],
            right: [
                "The right column begins here and must",
                "come only after the whole left column",
                "has been read, even though both of",
                "them share the same baselines on the",
                "page, and the right column ends here.",
            ]
        )
        book.truth.orderedPhrases = [
            "left column begins here",
            "left column ends right here",
            "right column begins here",
            "right column ends here",
        ]
        book.paragraph(
            """
            After the columns, a full-width paragraph returns to a single column, which closes \
            this short chapter and checks that the layout switches back correctly afterwards.
            """
        )
        book.newPage()
        book.heading(level: 2, "Closing remarks")
        book.paragraph(
            """
            The ideas in these notes come back in every later course. Revisit them whenever a \
            program feels slower than it should, and start by writing down what you expect it to \
            cost. Comparing that expectation with a measurement is how intuition gets built.
            """
        )
        book.heading(level: 3, "Further reading")
        book.list([
            (0, "•", "Any standard textbook on algorithms and data structures."),
            (0, "•", "The documentation of the language you use every day."),
        ])
    }
}

/// `book.pdf` with its fonts renamed to Computer Modern in `/BaseFont` and `/FontName`. PDFKit
/// keeps reporting the embedded program's name, while a real LaTeX PDF would say `CMR10`, so
/// this is what proves that font facts come from the content stream.
enum FontPatchFixture {
    private static let renames = [
        ("Menlo-Regular", "CMTT10xRegula"),
        ("STIXTwoMath-Regular", "CMMI10xMathItalicXX"),
        ("Helvetica-Bold", "CMBX12xxxxBold"),
        ("+Helvetica", "+CMSS12xxx"),
        ("Times-Roman", "CMR10xRoman"),
        ("Times-Bold", "CMBX10Bold"),
        ("Times-Italic", "CMTI10Italic"),
    ]

    static func bookWithComputerModernNames(
        from book: (data: Data, truth: GroundTruth)
    ) throws -> Fixture {
        var data = book.data
        for (original, replacement) in renames {
            data = PDFNormalizer.replacing(original, with: replacement, in: data)
        }
        return Fixture(fileName: "book-cm.pdf", data: data, truth: book.truth)
    }
}

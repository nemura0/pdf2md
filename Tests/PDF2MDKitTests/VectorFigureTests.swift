import CoreGraphics
import Testing

@testable import PDF2MDKit

@Suite("Vector figures")
struct VectorFigureTests {
    private let page = CGSize(width: 480, height: 680)

    /// Two class boxes with a line between them, the way TikZ draws them: a filled box, an
    /// outline, and a rule for each compartment.
    private var diagramShapes: [CGRect] {
        [
            CGRect(x: 100, y: 200, width: 80, height: 60),
            CGRect(x: 100, y: 200, width: 80, height: 60),
            CGRect(x: 100, y: 220, width: 80, height: 0),
            CGRect(x: 180, y: 230, width: 60, height: 0),
            CGRect(x: 240, y: 200, width: 80, height: 60),
            CGRect(x: 240, y: 200, width: 80, height: 60),
        ]
    }

    private var diagramWords: [Word] {
        words("Persona", x: 110, y: 215) + words("nombre", x: 110, y: 235)
            + words("tiene", x: 195, y: 227) + words("Celular", x: 250, y: 215)
            + words("modelo", x: 250, y: 235)
    }

    private func find(
        shapes: [CGRect],
        words: [Word],
        tables: [CGRect] = [],
        figures: [CGRect] = []
    ) -> [CGRect] {
        VectorFigures.find(
            shapes: shapes,
            rules: [],
            lines: LineBuilder.lines(from: words),
            tables: tables,
            figures: figures,
            pageSize: page
        )
    }

    @Test("shapes that touch make one figure, around all of them")
    func oneDiagram() throws {
        let found = find(shapes: diagramShapes, words: diagramWords)
        let figure = try #require(found.first)
        #expect(found.count == 1)
        #expect(figure.minX <= 100 && figure.maxX >= 320)
        #expect(figure.minY <= 200 && figure.maxY >= 260)
    }

    @Test("separate drawings make separate figures")
    func twoDiagrams() {
        let below = diagramShapes.map { $0.offsetBy(dx: 0, dy: 200) }
        let found = find(
            shapes: diagramShapes + below,
            words: diagramWords + words("Otra", x: 110, y: 415)
        )
        #expect(found.count == 2)
    }

    @Test("a drawing labelled in monospace is still a drawing")
    func monospaceLabels() {
        let mono =
            words("x = 5", x: 110, y: 215, font: .mono)
            + words("y = 7", x: 250, y: 215, font: .mono)
        #expect(find(shapes: diagramShapes, words: mono).count == 1)
    }

    @Test("a shape alone is a rule or a box, not a drawing")
    func tooFewShapes() {
        let box = [diagramShapes[0], diagramShapes[1]]
        #expect(find(shapes: box, words: words("Nota", x: 110, y: 215)).isEmpty)
    }

    @Test("marks too small to see as shapes don't make a figure")
    func bullets() {
        let bullets = (0..<6).map { CGRect(x: 100, y: 200 + Double($0) * 5, width: 3, height: 3) }
        #expect(find(shapes: bullets, words: []).isEmpty)
    }

    @Test("a listing's background is code, not a drawing")
    func listingBackground() {
        let stripes = (0..<6).map {
            CGRect(x: 40, y: 200 + Double($0) * 11, width: 400, height: 11)
        }
        let code = (0..<6).flatMap {
            words("int x = \($0);", x: 50, y: 209 + Double($0) * 11, font: .mono)
        }
        #expect(find(shapes: stripes, words: code).isEmpty)
    }

    @Test("shaded code in a paragraph is still a paragraph")
    func shadedSpans() {
        let spans = [
            CGRect(x: 100, y: 200, width: 30, height: 12),
            CGRect(x: 140, y: 212, width: 30, height: 12),
            CGRect(x: 100, y: 224, width: 30, height: 12),
        ]
        let prose =
            words("una linea de parrafo con la clase App en medio", x: 40, y: 209)
            + words("y otra linea con la clase Main en el medio", x: 40, y: 221)
            + words("y una tercera linea con App en ella misma", x: 40, y: 233)
        #expect(find(shapes: spans, words: prose).isEmpty)
    }

    @Test("a frame of sentences is a note, not a drawing")
    func framedProse() {
        let frame = (0..<4).map { _ in CGRect(x: 40, y: 200, width: 400, height: 60) }
        let prose =
            words("Una nota enmarcada con un texto bastante largo para leer", x: 50, y: 215)
            + words("que sigue por otra linea igual de larga que la de arriba", x: 50, y: 227)
        #expect(find(shapes: frame, words: prose).isEmpty)
    }

    @Test("what a table or an image already holds isn't drawn again")
    func alreadyFound() {
        let area = CGRect(x: 90, y: 190, width: 240, height: 80)
        #expect(find(shapes: diagramShapes, words: diagramWords, tables: [area]).isEmpty)
        #expect(find(shapes: diagramShapes, words: diagramWords, figures: [area]).isEmpty)
    }

    @Test("bars in the page's margin are its furniture")
    func marginBars() {
        let bars = (0..<4).map { CGRect(x: 0, y: Double($0) * 4, width: 480, height: 30) }
        #expect(find(shapes: bars, words: words("Capitulo", x: 40, y: 20)).isEmpty)
    }

    @Test("labels just outside the shapes belong to the drawing")
    func nearbyLabel() throws {
        let cells = (0..<3).map { CGRect(x: 100 + Double($0) * 40, y: 300, width: 40, height: 16) }
        let figure = try #require(
            find(shapes: cells, words: words("[0] [1] [2]", x: 105, y: 295)).first
        )
        #expect(figure.minY < 290)
    }

    @Test("a sentence under the drawing isn't one of its labels")
    func captionStaysOut() throws {
        let cells = (0..<3).map { CGRect(x: 100 + Double($0) * 40, y: 300, width: 40, height: 16) }
        let caption = words(
            "Un parrafo normal que sigue debajo de la figura y ocupa bastante",
            x: 40,
            y: 330
        )
        let figure = try #require(find(shapes: cells, words: caption).first)
        #expect(figure.maxY < 325)
    }

    @Test("the same drawing has the same identity on any page, and other labels change it")
    func digests() {
        let moved = diagramShapes.map { $0.offsetBy(dx: 0, dy: 90) }
        let movedWords =
            words("Persona", x: 110, y: 305) + words("nombre", x: 110, y: 325)
            + words("tiene", x: 195, y: 317) + words("Celular", x: 250, y: 305)
            + words("modelo", x: 250, y: 325)
        let rect = CGRect(x: 100, y: 200, width: 220, height: 60)
        let first = VectorFigures.digest(
            of: rect,
            shapes: diagramShapes,
            words: diagramWords
        )
        let second = VectorFigures.digest(
            of: rect.offsetBy(dx: 0, dy: 90),
            shapes: moved,
            words: movedWords
        )
        let relabelled = VectorFigures.digest(
            of: rect,
            shapes: diagramShapes,
            words: diagramWords + words("otra", x: 110, y: 250)
        )
        #expect(first == second)
        #expect(first != relabelled)
    }
}

@Suite("Diagram labels")
struct DiagramLabelTests {
    private func labels(_ words: [Word]) -> [String] {
        DiagramLabels.lines(from: LineBuilder.lines(from: words))
    }

    @Test("labels keep their places, so columns still read as columns")
    func keepsColumns() throws {
        let rendered = labels(
            words("App", x: 100, y: 200) + words("Sistema", x: 200, y: 200)
                + words("main()", x: 100, y: 212) + words("cargar()", x: 200, y: 212)
        )
        #expect(rendered.count == 2)
        let first = try #require(rendered[0].range(of: "Sistema")?.lowerBound)
        let second = try #require(rendered[1].range(of: "cargar()")?.lowerBound)
        #expect(
            rendered[0].distance(from: rendered[0].startIndex, to: first)
                == rendered[1].distance(from: rendered[1].startIndex, to: second)
        )
        #expect(rendered[0].hasPrefix("App"))
    }

    @Test("a phrase keeps single spaces, however its letters measure")
    func phrase() {
        #expect(labels(words("1..* tiene 1", x: 100, y: 200)) == ["1..* tiene 1"])
    }

    @Test("labels stay apart even when their places collide")
    func noCollisions() {
        let narrow = "abcdefghijklmnopqrstuvwxyz"
        let rendered = labels(
            words(narrow, x: 100, y: 200, size: 4) + words("z", x: 170, y: 200, size: 4)
                + words(narrow.uppercased(), x: 100, y: 230, size: 20)
        )
        #expect(rendered[0] == narrow + " z")
    }

    @Test("no labels, no lines")
    func empty() {
        #expect(labels([]).isEmpty)
    }
}

@Suite("Vector figures drawn as one path")
struct OnePathFigureTests {
    private let page = CGSize(width: 480, height: 680)

    @Test("a box with compartments, drawn as one path, is a drawing")
    func classBox() {
        let box = CGRect(x: 160, y: 400, width: 170, height: 90)
        let rules = [
            RuleSegment(startX: 160, startY: 420, endX: 330, endY: 420),
            RuleSegment(startX: 160, startY: 440, endX: 330, endY: 440),
        ]
        let page = words("App", x: 230, y: 415) + words("-nombres", x: 170, y: 435)
        let found = VectorFigures.find(
            shapes: [box],
            rules: rules,
            lines: LineBuilder.lines(from: page),
            tables: [],
            figures: [],
            pageSize: self.page
        )
        #expect(found.count == 1)
    }

    @Test("a plain frame around a few words is only a frame")
    func plainFrame() {
        let box = CGRect(x: 160, y: 400, width: 170, height: 40)
        let rules = [
            RuleSegment(startX: 160, startY: 400, endX: 330, endY: 400),
            RuleSegment(startX: 160, startY: 440, endX: 330, endY: 440),
            RuleSegment(startX: 160, startY: 400, endX: 160, endY: 440),
            RuleSegment(startX: 330, startY: 400, endX: 330, endY: 440),
        ]
        let found = VectorFigures.find(
            shapes: [box],
            rules: rules,
            lines: LineBuilder.lines(from: words("Importante", x: 170, y: 420)),
            tables: [],
            figures: [],
            pageSize: self.page
        )
        #expect(found.isEmpty)
    }
}

@Suite("Diagram labels that stack")
struct StackedLabelTests {
    private func measured(_ text: String, x: Double, top: Double, baseline: Double, size: Double)
        -> Word
    {
        Word(
            text: text,
            rect: CGRect(x: x, y: top, width: Double(text.count) * size / 2, height: size * 1.46),
            baseline: baseline,
            size: size,
            font: .body
        )
    }

    /// Measured on a real book's diagram: a mark beside a line, at a height between two rows.
    @Test("a taller mark between two rows doesn't join them into one")
    func bridgedRows() throws {
        let input = [
            measured("marca", x: 159.3, top: 363.8, baseline: 374.2, size: 9),
            measured("modelo", x: 159.3, top: 374.8, baseline: 385.1, size: 9),
            measured("*", x: 230, top: 368, baseline: 379, size: 10),
        ]
        let rows = DiagramLabels.lines(from: LineBuilder.lines(from: input))
        #expect(rows.count == 2)
        #expect(rows[0].hasPrefix("marca") && rows[0].hasSuffix("*"))
        #expect(rows[1] == "modelo")
    }

    @Test("a label with a script stays on its row")
    func script() {
        let input = [
            word("x", x: 72, y: 100),
            word("2", x: 77, y: 96, size: 7, isGlued: true),
            word("i", x: 77, y: 102, size: 7, isGlued: true),
        ]
        #expect(DiagramLabels.lines(from: LineBuilder.lines(from: input)).count == 1)
    }
}

@Suite("Vector figures with framed captions")
struct FramedCaptionTests {
    private let page = CGSize(width: 482, height: 680)
    /// Three circles spread out: a drawing, whose shapes are far from one another's reach.
    private let circles = [
        CGRect(x: 100, y: 300, width: 22, height: 22),
        CGRect(x: 105, y: 303, width: 12, height: 12),
        CGRect(x: 300, y: 400, width: 22, height: 22),
        CGRect(x: 305, y: 403, width: 12, height: 12),
        CGRect(x: 110, y: 318, width: 200, height: 90),
    ]
    private let frame = CGRect(x: 60, y: 240, width: 120, height: 50)

    private func find(frame: CGRect, lines: [TextLine]) -> [CGRect] {
        VectorFigures.find(
            shapes: circles + [frame],
            rules: [],
            lines: lines,
            tables: [],
            figures: [],
            pageSize: page
        )
    }

    @Test("a framed caption beside a drawing belongs to it")
    func captionBeside() throws {
        let caption = [
            line("Dominio del problema", x: 70, y: 256), line("Conceptos", x: 70, y: 268),
        ]
        let found = try #require(find(frame: frame, lines: caption).first)
        #expect(found.minY <= frame.minY && found.maxY >= circles[3].maxY)
        #expect(find(frame: frame, lines: caption).count == 1)
    }

    @Test("a framed caption far from the drawing is left out")
    func captionFarAway() throws {
        let far = frame.offsetBy(dx: 0, dy: -120)
        let caption = [line("Otra cosa", x: 70, y: far.minY + 16)]
        let found = try #require(find(frame: far, lines: caption).first)
        #expect(found.minY > frame.minY)
    }

    @Test("shaded code in a paragraph just above a drawing is left out")
    func shadedCodeNearby() throws {
        let shaded = CGRect(x: 100, y: 282, width: 30, height: 11)
        let sentence = line(
            "Una frase larga con algo de codigo sombreado en medio que sigue hasta el margen",
            x: 30,
            y: 291
        )
        let found = try #require(find(frame: shaded, lines: [sentence]).first)
        #expect(found.minY > shaded.minY)
    }
}

@Suite("Vector figures on hostile pages")
struct HostileVectorFigureTests {
    private let page = CGSize(width: 600, height: 800)

    private func find(shapes: [CGRect], lines: [TextLine] = []) -> [CGRect] {
        VectorFigures.find(
            shapes: shapes,
            rules: [],
            lines: lines,
            tables: [],
            figures: [],
            pageSize: page
        )
    }

    /// `CGRect.null` holds infinities, which the spool can't encode, and the page would be lost.
    @Test("a drawing entirely off the page isn't a drawing")
    func offThePage() {
        let shapes = (0..<3).map { CGRect(x: 700 + Double($0) * 10, y: 400, width: 60, height: 40) }
        #expect(find(shapes: shapes).isEmpty)
    }

    @Test("a drawing partly off the page is clipped to it")
    func partlyOff() throws {
        let shapes = (0..<3).map { CGRect(x: 560 + Double($0) * 10, y: 400, width: 60, height: 40) }
        let found = try #require(find(shapes: shapes).first)
        #expect(found.maxX <= page.width)
    }

    /// Every drawing against every small cluster against every line took 11.5 s at about this size
    /// in a release build, with the page's slot held all along.
    @Test("a page of many small clusters doesn't take long")
    func manyClusters() {
        // A grid wide enough apart that no two of these join: 5-point marks on a 12-point pitch.
        let cell = { (index: Int) in
            CGRect(x: Double(index % 49) * 12, y: 60 + Double(index / 49) * 12, width: 5, height: 5)
        }
        let drawings = (0..<600).flatMap { [cell($0), cell($0), cell($0)] }
        let parts = (600..<2600).map(cell)
        let lines = (0..<500).map { index in
            line("a", x: Double(index % 49) * 12, y: 60 + Double(index / 49) * 12)
        }
        let start = ContinuousClock.now
        _ = find(shapes: drawings + parts, lines: lines)
        #expect(ContinuousClock.now - start < .seconds(20))
    }

    @Test("a huge shape in a digest doesn't stop the conversion")
    func hugeShapeInDigest() {
        let rect = CGRect(x: 0, y: 0, width: 1e30, height: 1e30)
        let shape = CGRect(x: 1e29, y: 1e29, width: 1e29, height: 1e29)
        #expect(!VectorFigures.digest(of: rect, shapes: [shape], words: []).isEmpty)
    }
}

@Suite("Diagram labels on hostile pages")
struct HostileDiagramLabelTests {
    @Test("a word absurdly far away doesn't stop the conversion")
    func farAway() throws {
        let lines = DiagramLabels.lines(from: [
            line("a", x: 0, y: 100), line("b", x: 1e30, y: 100),
        ])
        let row = try #require(lines.first)
        #expect(row.hasSuffix("b"))
        #expect(row.count < 200)
    }
}

@Suite("Vector figures with parts and labels beside them")
struct DrawingPartsTests {
    private let page = CGSize(width: 482, height: 680)
    /// A box, its outline and its compartment: a drawing from x 200 to 330, y 300 to 380.
    private let box = [
        CGRect(x: 200, y: 300, width: 130, height: 80),
        CGRect(x: 200, y: 300, width: 130, height: 80),
        CGRect(x: 200, y: 320, width: 130, height: 10),
    ]

    private func find(extra: [CGRect] = [], lines: [TextLine] = []) -> [CGRect] {
        VectorFigures.find(
            shapes: box + extra,
            rules: [],
            lines: lines,
            tables: [],
            figures: [],
            pageSize: page
        )
    }

    @Test("an arrow stopping short of a drawing belongs to it")
    func arrow() throws {
        let found = try #require(find(extra: [CGRect(x: 150, y: 330, width: 38, height: 14)]).first)
        #expect(found.minX <= 150)
    }

    @Test("a straight arrow level with a drawing belongs to it")
    func straightArrow() throws {
        let found = try #require(find(extra: [CGRect(x: 150, y: 340, width: 38, height: 0)]).first)
        #expect(found.minX <= 150)
    }

    @Test("a lone rule close to a drawing stays out, since it can be a footnote's")
    func loneRule() throws {
        let found = try #require(find(extra: [CGRect(x: 100, y: 392, width: 170, height: 0)]).first)
        #expect(found.maxY < 392)
    }

    @Test("a short label beside a drawing joins it, however far it sticks out")
    func labelToTheRight() throws {
        let label = line("acelerar [vel<max] / vel++", x: 334, y: 330)
        let found = try #require(find(lines: [label]).first)
        #expect(found.maxX >= label.rect.maxX)
    }

    @Test("a label partly over a drawing's left side joins it")
    func labelOverTheLeft() throws {
        let label = line("instancia1", x: 170, y: 330)
        let found = try #require(find(lines: [label]).first)
        #expect(found.minX <= 170)
    }

    @Test("the last line of a paragraph beside a drawing stays out")
    func sentenceBeside() throws {
        let found = try #require(find(lines: [line("de otra manera.", x: 334, y: 330)]).first)
        #expect(found.maxX < 340)
    }

    /// A real book's short listing beside a shaded box of output reads as a label otherwise.
    @Test("a line of a listing beside a drawing stays out")
    func listingBeside() throws {
        let found = try #require(find(lines: [line("Este", x: 334, y: 330, font: .mono)]).first)
        #expect(found.maxX < 340)
    }

    @Test("a line with more words than a label stays out")
    func longLineBeside() throws {
        let text = "una linea de un parrafo con muchas palabras que sigue"
        let found = try #require(find(lines: [line(text, x: 334, y: 330)]).first)
        #expect(found.maxX < 340)
    }

    @Test("a short line below a drawing stays out")
    func lineBelow() throws {
        let found = try #require(find(lines: [line("Por ejemplo", x: 30, y: 420)]).first)
        #expect(found.maxY < 400)
    }
}

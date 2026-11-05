import CoreGraphics
import Testing

@testable import PDF2MDKit

/// Geometry measured on a real LuaLaTeX book. PDFKit's word rect follows the font's bounding box,
/// so it is taller than the leading and reaches the baseline of the line above.
@Suite("RunIndex")
struct RunIndexTests {
    private func run(
        x: ClosedRange<Double>,
        baseline: Double,
        size: Double = 10,
        style: FontStyle = .body
    ) -> TextRun {
        TextRun(
            originX: x.lowerBound,
            endX: x.upperBound,
            baseline: baseline,
            size: size,
            style: style,
            isHorizontal: true,
            hasReliableEnd: true
        )
    }

    @Test("a word takes its own line's run, not the one above that its rect reaches")
    func ownLineOverLineAbove() throws {
        let above = run(x: 23.15...122.61, baseline: 72.37, size: 8, style: .mono)
        let own = run(x: 22.95...27.18, baseline: 81.83, size: 8, style: .mono)
        let rect = CGRect(x: 22.95, y: 73.75, width: 4.23, height: 10.63)

        let best = try #require(RunIndex(runs: [above, own]).bestRun(for: rect))

        #expect(best.baseline == 81.83)
    }

    @Test("code on the line above doesn't split a body word")
    func noFalseFontBoundary() {
        let above = run(x: 100.99...106.22, baseline: 173.99, style: .mono)
        let own = run(x: 22.68...253.24, baseline: 185.94)
        let rect = CGRect(x: 96, y: 174.45, width: 20, height: 14.57)

        let runs = RunIndex(runs: [above, own]).distinctRuns(overlapping: rect)

        #expect(runs.map(\.baseline) == [185.94])
    }

    @Test("a superscript inside a word still crosses a boundary")
    func superscriptIsKept() {
        let base = run(x: 72...77, baseline: 100)
        let script = run(x: 77...81, baseline: 96.4, size: 7)
        let rect = CGRect(x: 72, y: 88.5, width: 9, height: 14.6)

        let runs = RunIndex(runs: [base, script]).distinctRuns(overlapping: rect)

        #expect(runs.map(\.baseline) == [100, 96.4])
    }

    @Test("a subscript inside a word still crosses a boundary")
    func subscriptIsKept() {
        let base = run(x: 72...77, baseline: 100)
        let script = run(x: 77...81, baseline: 101.5, size: 7)
        let rect = CGRect(x: 72, y: 88.5, width: 9, height: 15.1)

        let runs = RunIndex(runs: [base, script]).distinctRuns(overlapping: rect)

        #expect(runs.map(\.baseline) == [100, 101.5])
    }

    @Test("with nothing else in reach, the nearest run is still used")
    func onlyRunAbove() throws {
        let above = run(x: 20...60, baseline: 72.37, size: 8, style: .mono)
        let rect = CGRect(x: 22.95, y: 73.75, width: 4.23, height: 10.63)

        let best = try #require(RunIndex(runs: [above]).bestRun(for: rect))

        #expect(best.baseline == 72.37)
    }
}

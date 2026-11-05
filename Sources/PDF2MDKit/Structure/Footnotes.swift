import CoreGraphics
import Foundation

/// A page's lines without its footnotes, and those notes as blocks.
struct FootnotePage: Equatable {
    var lines: [TextLine]
    var notes: [Block]
}

/// Takes footnotes out of a page's text and links them to their markers. Left in the flow, a note
/// lands between two parts of a sentence, its marker sticks to the word before it (`Java5`), and
/// the first word of the note gets the number glued on (`1Ingeniería`).
enum Footnotes {
    /// LaTeX's rule is 40% of the text and Word's is about a third of it. As shares of the page.
    private static let ruleShares = 0.1...0.5
    /// A long note can start this high on a page.
    private static let highestRuleShare = 0.4
    /// The rule starts at the text's margin, and notes can be indented from it. On a page of
    /// nothing but a listing and a running head, a note may be the only line that says so.
    private static let lineStartsFromRule = -6.0...16.0
    private static let noteSizeShare = 0.95
    /// Like a math script: clearly smaller than its line, and off its baseline.
    private static let markerSizeShare = 0.85
    private static let markerRiseShare = 0.12
    private static let maximumMarkerLength = 3

    private struct Note {
        var marker: String
        var fragments: [(words: [Word], line: TextLine)] = []
    }

    static func separate(
        lines: [TextLine],
        rules: [RuleSegment],
        blockers: [CGRect],
        pageIndex: Int,
        bodySize: Double,
        pageSize: CGSize
    ) -> FootnotePage {
        let unchanged = FootnotePage(lines: lines, notes: [])
        for rule in rules
        where isSeparator(rule, lines: lines, blockers: blockers, pageSize: pageSize) {
            let below = lines.filter { $0.baseline > rule.startY }
            let (noteLines, others) = split(below, bodySize: bodySize)
            guard others.allSatisfy(isPageNumber), let notes = notes(in: noteLines) else {
                continue
            }
            let above = lines.filter { $0.baseline <= rule.startY }
            return linked(notes, body: above, kept: others, pageIndex: pageIndex)
        }
        return unchanged
    }

    private static func isSeparator(
        _ rule: RuleSegment,
        lines: [TextLine],
        blockers: [CGRect],
        pageSize: CGSize
    ) -> Bool {
        let start = min(rule.startX, rule.endX)
        let length = abs(rule.endX - rule.startX)
        let middle = CGPoint(x: start + length / 2, y: rule.startY)
        return rule.isHorizontal && ruleShares.contains(length / pageSize.width)
            && rule.startY >= pageSize.height * highestRuleShare
            // Not the page's leftmost line: a listing's gutter can stick out past the text.
            && lines.contains { lineStartsFromRule.contains(Double($0.rect.minX) - start) }
            && !blockers.contains { $0.contains(middle) }
    }

    private static func split(
        _ below: [TextLine],
        bodySize: Double
    ) -> (notes: [TextLine], others: [TextLine]) {
        let notes = below.filter { $0.size <= bodySize * noteSizeShare }
        let others = below.filter { $0.size > bodySize * noteSizeShare }
        return (notes, others)
    }

    private static func isPageNumber(_ line: TextLine) -> Bool {
        line.words.count == 1 && TextLine.isPlainNumber(line.words[0])
    }

    // MARK: Reading notes

    /// Each marker starts a note, and several can share a line. Nil if the first has no marker: a
    /// short rule with small print under it can be a source line or a signature.
    private static func notes(in lines: [TextLine]) -> [Note]? {
        var notes: [Note] = []
        for line in lines.sorted(by: { ($0.baseline, $0.rect.minX) < ($1.baseline, $1.rect.minX) })
        {
            var run: [Word] = []
            for word in line.words {
                if isMarker(word, in: line) {
                    if !run.isEmpty, !notes.isEmpty {
                        notes[notes.count - 1].fragments.append((run, line))
                    }
                    run = []
                    notes.append(Note(marker: word.text))
                } else {
                    run.append(word)
                }
            }
            guard !notes.isEmpty else { return nil }
            if !run.isEmpty { notes[notes.count - 1].fragments.append((run, line)) }
        }
        return notes.isEmpty ? nil : notes
    }

    private static func isMarker(_ word: Word, in line: TextLine) -> Bool {
        !word.font.isMonospace && word.text.count <= maximumMarkerLength
            && word.size <= line.size * markerSizeShare
            && line.baseline - word.baseline >= line.size * markerRiseShare
    }

    private static func text(of note: Note) -> String {
        var text = ""
        var previousIsCode = false
        for fragment in note.fragments {
            let piece = InlineRenderer.render(fragment.words, in: fragment.line)
            let isCode = fragment.words.allSatisfy(\.font.isMonospace)
            if text.isEmpty {
                text = piece
            } else if text.hasSuffix("-"), piece.first?.isLowercase == true {
                text = String(text.dropLast()) + piece
            } else {
                // A URL breaks across lines with no hyphen, and a space would end it.
                text += (previousIsCode && isCode ? "" : " ") + piece
            }
            previousIsCode = isCode
        }
        return text
    }

    // MARK: Linking

    private static func linked(
        _ notes: [Note],
        body: [TextLine],
        kept: [TextLine],
        pageIndex: Int
    ) -> FootnotePage {
        var lines = body
        var blocks: [Block] = []
        for (offset, note) in notes.enumerated() {
            let name = note.marker.allSatisfy(\.isLetterOrNumber) ? note.marker : String(offset + 1)
            let label = "p\(pageIndex + 1)-\(name)"
            if link(marker: note.marker, label: label, in: &lines) {
                blocks.append(.footnote(label: label, text: text(of: note)))
            } else {
                let marker = "\\[" + InlineRenderer.escape(note.marker) + "\\]"
                blocks.append(.footnote(label: nil, text: marker + " " + text(of: note)))
            }
        }
        return FootnotePage(lines: lines + kept, notes: blocks)
    }

    /// LaTeX sets punctuation after a marker in the marker's size, as in `JRE3.`, so one word holds
    /// both.
    private static func isReference(_ word: Word, to marker: String) -> Bool {
        guard word.footnote == nil, word.text.hasPrefix(marker) else { return false }
        return word.text.dropFirst(marker.count).allSatisfy(\.isPunctuation)
    }

    private static let trailingPunctuation: Set<Character> = [",", ".", ";", ":", ")", "!", "?"]

    /// The marker's first appearance in the text.
    private static func link(marker: String, label: String, in lines: inout [TextLine]) -> Bool {
        let order = lines.indices.sorted { lines[$0].baseline < lines[$1].baseline }
        for index in order {
            let line = lines[index]
            guard
                let position = line.words.firstIndex(where: {
                    isReference($0, to: marker) && isMarker($0, in: line)
                })
            else { continue }
            var words = line.words
            words[position].text = String(words[position].text.dropFirst(marker.count))
            words[position].footnote = label
            words[position].isGlued = true
            // The comma after a marker can be a word of its own, and it stays with the reference.
            let next = position + 1
            if next < words.count, words[next].text.allSatisfy(trailingPunctuation.contains) {
                words[next].isGlued = true
            }
            lines[index] = TextLine(words: words)
            return true
        }
        return false
    }
}

extension Character {
    fileprivate var isLetterOrNumber: Bool { isLetter || isNumber }
}

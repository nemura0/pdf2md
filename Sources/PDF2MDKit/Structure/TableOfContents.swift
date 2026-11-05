import Foundation

/// Recognizes a page of a printed table of contents. Its page numbers mean nothing in the output,
/// its entries repeat the headings, and in a real book its dot leaders alone were 14,256 characters.
public enum TableOfContents {
    private static let minimumLeaderRows = 5
    /// Most rows are entries. The rest are a title and a page number.
    private static let minimumEntryShare = 0.7
    private static let sameRowTolerance = 2.0

    /// True for a page mostly made of rows with a dot leader, whose page numbers never go down.
    /// That last part keeps out a price list, whose rows look the same.
    public static func isListing(_ lines: [TextLine]) -> Bool {
        var leaderRows = 0
        var entryRows = 0
        var textRows = 0
        var numbers: [Int] = []
        for row in rows(of: lines) where row.contains(where: \.isLetter) {
            textRows += 1
            let last = row.split(whereSeparator: \.isWhitespace).last.map(String.init)
            let number = last.flatMap { Int($0) }
            let hasLeader = row.contains(". . .") || row.contains("...")
            if hasLeader { leaderRows += 1 }
            if hasLeader || number != nil { entryRows += 1 }
            if let number { numbers.append(number) }
        }
        guard leaderRows >= minimumLeaderRows,
            Double(entryRows) >= Double(textRows) * minimumEntryShare
        else { return false }
        return zip(numbers, numbers.dropFirst()).allSatisfy { $0 <= $1 }
    }

    /// Text joined per row, top to bottom. A page number can sit far from its leader, and then
    /// it's a line of its own.
    private static func rows(of lines: [TextLine]) -> [String] {
        let sorted = lines.sorted {
            ($0.baseline, Double($0.rect.minX)) < ($1.baseline, Double($1.rect.minX))
        }
        var rows: [String] = []
        var rowBaseline = -Double.infinity
        for line in sorted {
            if line.baseline - rowBaseline <= sameRowTolerance, let last = rows.last {
                rows[rows.count - 1] = last + " " + line.text
            } else {
                rows.append(line.text)
                rowBaseline = line.baseline
            }
        }
        return rows
    }
}

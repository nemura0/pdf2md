import Foundation

/// Decides, in page order, which spooled crops reach the output and under what name.
struct FigureNamer {
    private let repeatedDigests: Set<String>
    private let cropDirectory: URL
    private let assetsName: String?
    private var namesByDigest: [String: String] = [:]
    private var nextOrdinalByPage: [Int: Int] = [:]

    private(set) var images: [(source: URL, name: String)] = []

    init(repeatedDigests: Set<String>, cropDirectory: URL, assetsName: String?) {
        self.repeatedDigests = repeatedDigests
        self.cropDirectory = cropDirectory
        self.assetsName = assetsName
    }

    func hasCrop(for digest: String) -> Bool {
        namesByDigest[digest] != nil
    }

    /// The relative link for a figure, or nil if it's dropped: a logo repeated across the
    /// document, or a crop that couldn't be made. An identical image links to its first copy.
    mutating func link(for figure: FigureCandidate, pageIndex: Int) -> String? {
        guard let assetsName, let cropFile = figure.cropFile,
            !repeatedDigests.contains(figure.digest)
        else { return nil }
        if let known = namesByDigest[figure.digest] { return "\(assetsName)/\(known)" }

        let ordinal = nextOrdinalByPage[pageIndex, default: 1]
        nextOrdinalByPage[pageIndex] = ordinal + 1
        let fileExtension = (cropFile as NSString).pathExtension
        let name = String(format: "p%04d-%02d.", pageIndex + 1, ordinal) + fileExtension
        namesByDigest[figure.digest] = name
        images.append((cropDirectory.appendingPathComponent(cropFile), name))
        return "\(assetsName)/\(name)"
    }
}

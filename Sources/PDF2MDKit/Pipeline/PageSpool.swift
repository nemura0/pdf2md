import Foundation

/// One Codable page record per file, read back in order at emit (ADR-0006).
public struct PageSpool: Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func write(_ record: PageRecord) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: url(forPage: record.index), options: .atomic)
    }

    public func read(page: Int) throws -> PageRecord {
        let data = try Data(contentsOf: url(forPage: page))
        return try JSONDecoder().decode(PageRecord.self, from: data)
    }

    public func imageURL(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(forPage page: Int) -> URL {
        directory.appendingPathComponent(String(format: "p%07d.json", page))
    }
}

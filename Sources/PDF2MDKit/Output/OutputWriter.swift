import Darwin
import Foundation

/// A reserved output: an empty placeholder (unless overwriting) and an assets directory.
public struct ReservedOutput: Sendable, Equatable {
    public var markdown: URL
    public var assets: URL?
    /// Written during emit, then renamed over `markdown`.
    public var temporary: URL
    public var didFallBack: Bool
    public var isOverwrite: Bool
    /// True if this run created `assets`, so commit may remove it when it stays empty.
    public var ownsAssets: Bool
}

/// Reserves output names atomically and commits finished output.
public enum OutputWriter {
    private static let maximumSuffix = 10_000

    /// `beforeCreating` runs before any path is created, so a crash can't leave a path the job
    /// manifest doesn't know about. `didAbandon` retracts a path that turned out to belong to
    /// someone else, so cleanup can never touch it (A10).
    public static func reserve(
        pdf: URL,
        options: ConvertOptions,
        downloads: URL,
        beforeCreating: ([URL]) throws -> Void,
        didAbandon: ([URL]) throws -> Void = { _ in }
    ) throws -> ReservedOutput {
        let stem = pdf.deletingPathExtension().lastPathComponent
        let directory = options.outputDirectory ?? pdf.deletingLastPathComponent()
        do {
            return try reserve(
                stem: stem,
                in: directory,
                options: options,
                didFallBack: false,
                beforeCreating: beforeCreating,
                didAbandon: didAbandon
            )
        } catch let error as ReservationError where error.isPermissionProblem {
            if let explicit = options.outputDirectory {
                throw ConversionFailure("can't write to \(explicit.path)")
            }
            do {
                return try reserve(
                    stem: stem,
                    in: downloads,
                    options: options,
                    didFallBack: true,
                    beforeCreating: beforeCreating,
                    didAbandon: didAbandon
                )
            } catch let inner as ReservationError {
                throw ConversionFailure("can't write output: \(inner.message)")
            }
        } catch let error as ReservationError {
            throw ConversionFailure("can't write output: \(error.message)")
        }
    }

    /// Moves images, renames the temp file over the placeholder, then drops empty assets. A crash
    /// before the rename leaves a zero-byte placeholder, which marks it as unfinished.
    public static func commit(
        _ output: ReservedOutput,
        images: [(source: URL, name: String)]
    ) throws {
        let manager = FileManager.default
        if let assets = output.assets {
            if !manager.fileExists(atPath: assets.path), !images.isEmpty {
                try manager.createDirectory(at: assets, withIntermediateDirectories: true)
            }
            for image in images {
                let target = assets.appendingPathComponent(image.name)
                try? manager.removeItem(at: target)
                try manager.moveItem(at: image.source, to: target)
            }
        }
        guard rename(output.temporary.path, output.markdown.path) == 0 else {
            throw ConversionFailure("couldn't finish \(output.markdown.lastPathComponent)")
        }
        if let assets = output.assets, output.ownsAssets { rmdir(assets.path) }
    }

    // MARK: Reservation

    private struct ReservationError: Error {
        var code: Int32
        var path: String

        var isPermissionProblem: Bool { code == EACCES || code == EPERM || code == EROFS }
        var message: String { "\(path): \(String(cString: strerror(code)))" }
    }

    private static func reserve(
        stem: String,
        in directory: URL,
        options: ConvertOptions,
        didFallBack: Bool,
        beforeCreating: ([URL]) throws -> Void,
        didAbandon: ([URL]) throws -> Void
    ) throws -> ReservedOutput {
        if options.overwrite {
            return try reserveOverwrite(
                stem: stem,
                in: directory,
                options: options,
                didFallBack: didFallBack,
                beforeCreating: beforeCreating
            )
        }
        for suffix in 0..<maximumSuffix {
            let name = suffix == 0 ? stem : "\(stem) (\(suffix))"
            let markdown = directory.appendingPathComponent(name + ".md")
            let assets =
                options.includeImages
                ? directory.appendingPathComponent(name + "_assets", isDirectory: true) : nil
            let temporary = temporaryURL(for: markdown)
            try beforeCreating([markdown, temporary])
            guard try createExclusively(markdown) else {
                try didAbandon([markdown, temporary])
                continue
            }
            if let assets {
                try beforeCreating([assets])
                guard try createDirectoryExclusively(assets) else {
                    unlink(markdown.path)
                    try didAbandon([markdown, temporary, assets])
                    continue
                }
            }
            return ReservedOutput(
                markdown: markdown,
                assets: assets,
                temporary: temporary,
                didFallBack: didFallBack,
                isOverwrite: false,
                ownsAssets: assets != nil
            )
        }
        throw ReservationError(code: EEXIST, path: directory.path)
    }

    /// Proves the folder is writable with the temp file, leaving the original alone until commit.
    private static func reserveOverwrite(
        stem: String,
        in directory: URL,
        options: ConvertOptions,
        didFallBack: Bool,
        beforeCreating: ([URL]) throws -> Void
    ) throws -> ReservedOutput {
        let markdown = directory.appendingPathComponent(stem + ".md")
        let assets =
            options.includeImages
            ? directory.appendingPathComponent(stem + "_assets", isDirectory: true) : nil
        let temporary = temporaryURL(for: markdown)
        try beforeCreating([temporary] + (assets.map { [$0] } ?? []))
        guard try createExclusively(temporary) else {
            throw ReservationError(code: EEXIST, path: temporary.path)
        }
        unlink(temporary.path)
        return ReservedOutput(
            markdown: markdown,
            assets: assets,
            temporary: temporary,
            didFallBack: didFallBack,
            isOverwrite: true,
            ownsAssets: false
        )
    }

    private static func temporaryURL(for markdown: URL) -> URL {
        markdown.deletingLastPathComponent().appendingPathComponent(
            // Short on purpose: a long PDF name must not fail just because of the temp name.
            ".\(UUID().uuidString)\(PartialOutput.temporarySuffix)"
        )
    }

    private static func createExclusively(_ url: URL) throws -> Bool {
        let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o644)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }
        if errno == EEXIST { return false }
        throw ReservationError(code: errno, path: url.path)
    }

    private static func createDirectoryExclusively(_ url: URL) throws -> Bool {
        if mkdir(url.path, 0o755) == 0 { return true }
        if errno == EEXIST { return false }
        throw ReservationError(code: errno, path: url.path)
    }
}

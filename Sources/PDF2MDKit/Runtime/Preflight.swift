import Darwin
import Foundation
import PDFKit

/// What a conversion needs to know before it reserves any output.
public struct PDFSummary: Sendable, Equatable {
    public var pageCount: Int
    public var metadataTitle: String?
    public var outline: [OutlineEntry] = []
}

/// Checks a file before any output is reserved. Runs in the file's child process, because a
/// malformed PDF can crash the framework. It opens its own short-lived document (A3).
public enum Preflight {
    private static let magicSearchLength = 1024

    public static func check(_ url: URL) throws -> PDFSummary {
        try materialize(url)
        return try open(url)
    }

    /// Makes sure the bytes are here, which can take a while for an online-only file.
    public static func materialize(_ url: URL) throws {
        try checkReadable(url)
        guard hasPDFMagic(url) else { throw ConversionFailure("not a PDF") }
    }

    /// Opens the document, the first step that can hang on a malformed file.
    public static func open(_ url: URL) throws -> PDFSummary {
        try autoreleasepool {
            guard let document = PDFDocument(url: url) else {
                // Measured: PDFKit and CoreGraphics both refuse a file whose page tree is empty,
                // so most zero-page PDFs land here rather than in the check below.
                throw ConversionFailure("corrupt or unreadable PDF")
            }
            if document.isLocked { throw ConversionFailure("password-protected") }
            guard document.pageCount > 0 else { throw ConversionFailure("the PDF has no pages") }
            let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            return PDFSummary(
                pageCount: document.pageCount,
                metadataTitle: title,
                outline: OutlineReader.entries(of: document)
            )
        }
    }

    /// True for an online-only file (Dropbox, iCloud) whose data isn't on disk yet.
    public static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        return stat(url.path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }

    private static func checkReadable(_ url: URL) throws {
        let wasDataless = isDataless(url)
        // Opening and reading is what makes a file provider materialize an online-only file.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure(forErrno: errno, url: url) }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw failure(forErrno: errno, url: url) }
        if info.st_mode & S_IFMT == S_IFDIR { throw ConversionFailure("it's a folder") }

        var byte: UInt8 = 0
        guard read(descriptor, &byte, 1) >= 0 else {
            if wasDataless { throw ConversionFailure("online-only, couldn't be downloaded") }
            throw failure(forErrno: errno, url: url)
        }
    }

    private static func hasPDFMagic(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: magicSearchLength) else { return false }
        return head.range(of: Data("%PDF-".utf8)) != nil
    }

    private static func failure(forErrno code: Int32, url: URL) -> ConversionFailure {
        switch code {
        case ENOENT:
            return ConversionFailure("file not found")
        case EPERM, EACCES:
            return ConversionFailure(permissionAdvice(for: url))
        default:
            return ConversionFailure("couldn't read: \(String(cString: strerror(code)))")
        }
    }

    /// Names the setting to change, since a bare "permission denied" gives no way forward.
    static func permissionAdvice(
        for url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let path = url.path
        let privacy = "System Settings > Privacy & Security"
        for folder in ["Desktop", "Documents", "Downloads"]
        where path.hasPrefix(home.appendingPathComponent(folder).path + "/") {
            return "no permission: allow the \(folder) Folder in \(privacy) > Files & Folders"
        }
        if path.hasPrefix("/Volumes/") {
            return "no permission: allow Removable Volumes in \(privacy) > Files & Folders"
        }
        return "no permission: allow access in \(privacy) > Full Disk Access"
    }
}

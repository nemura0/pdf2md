import Foundation

/// The seam around macOS notifications.
public protocol Notifying: Sendable {
    func send(_ text: String)
}

/// The words of a run's notifications.
public enum NotificationText {
    /// macOS shows about this much of a banner before cutting it off.
    private static let maximumLength = 200
    private static let logPointer = "Details: ~/Library/Logs/pdf2md/pdf2md.log"
    private static let cancelledReason = "cancelled"

    public static func started(fileCount: Int) -> String {
        fileCount == 1 ? "Converting 1 PDF…" : "Converting \(fileCount) PDFs…"
    }

    /// The headline, then each failure with its reason, as many as fit. The log gets the rest.
    public static func finished(_ summary: RunSummary) -> String {
        let wasCancelled = summary.outcomes.contains { $0.error == cancelledReason }
        var lines = [wasCancelled ? "Cancelled. \(summary.headline)" : summary.headline]
        let fallBacks = summary.outcomes.filter(\.didFallBack).count
        if fallBacks > 0 { lines.append("Folder not writable, saved to Downloads.") }

        let failures = summary.outcomes.filter { outcome in
            outcome.error != nil && outcome.error != cancelledReason
        }
        for (offset, failure) in failures.enumerated() {
            let line = "\(failure.input.lastPathComponent): \(failure.error ?? "")"
            let isLast = offset == failures.count - 1
            let reserve = isLast ? 0 : logPointer.count + 1
            guard length(of: lines + [line]) + reserve <= maximumLength else {
                lines.append(logPointer)
                break
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func length(of lines: [String]) -> Int {
        lines.reduce(lines.count - 1) { $0 + $1.count }
    }
}

/// Sends notifications through `osascript`. File names travel in `argv`, never in the script's
/// text, so a name can't inject AppleScript.
public struct OsascriptNotifier: Notifying {
    private static let defaultExecutable = "/usr/bin/osascript"
    private static let title = "Convert to Markdown"
    /// A stuck notification can't hold anything up for long. Under `--cancel`'s grace period, or
    /// the start notification could get a healthy supervisor killed.
    private static let timeoutSeconds = 5.0

    private let executable: String

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = environment["PDF2MD_OSASCRIPT"] ?? Self.defaultExecutable
    }

    public func send(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-e", "on run argv",
            "-e", "display notification (item 1 of argv) with title \"\(Self.title)\"",
            "-e", "end run",
            text,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            // The conversion itself is what matters, and the log has its result.
            return
        }
        let deadline = Date().addingTimeInterval(Self.timeoutSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            // SIGKILL, because ignored signals survive exec and a supervisor ignores SIGTERM.
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}

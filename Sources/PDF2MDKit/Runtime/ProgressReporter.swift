import Darwin
import Foundation
import Synchronization

/// Concise progress on stderr for foreground runs. Only a terminal gets the live page counter.
final class ProgressReporter: Sendable {
    private static let minimumInterval = 0.25
    private static let clearLine = "\r\u{1B}[K"

    private struct State {
        var lastDraw = Date.distantPast
        var hasLiveLine = false
    }

    private let isEnabled: Bool
    private let isTerminal: Bool
    private let state = Mutex(State())

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        self.isTerminal = isatty(STDERR_FILENO) == 1
    }

    func page(file: String, done: Int, total: Int) {
        guard isEnabled, isTerminal else { return }
        state.withLock { state in
            guard Date().timeIntervalSince(state.lastDraw) >= Self.minimumInterval else { return }
            state.lastDraw = Date()
            state.hasLiveLine = true
            Self.write("\(Self.clearLine)\(file): page \(done) of \(total)")
        }
    }

    func line(_ text: String) {
        guard isEnabled else { return }
        state.withLock { state in
            Self.write((state.hasLiveLine ? Self.clearLine : "") + text + "\n")
            state.hasLiveLine = false
        }
    }

    private static func write(_ text: String) {
        try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
    }
}

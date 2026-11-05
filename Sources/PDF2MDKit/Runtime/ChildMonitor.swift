import Darwin
import Foundation
import Synchronization

/// Reads one child's events until it exits, and kills it if its pages stop advancing.
final class ChildMonitor: Sendable {
    enum Ending: Sendable {
        case finished(ConversionReport)
        case failed(String)
        case crashed(signal: Int32?)
        case hung
    }

    /// A hard hang in CoreGraphics is what this catches. Generous, because a single page can
    /// legitimately be slow. It starts at `.opening`, once the file's data is here, so a slow
    /// Dropbox download never trips it, and a malformed file that hangs PDFKit's open does.
    private static let defaultWatchdogSeconds = 900.0
    private static let readSize = 65_536
    private static let checkInterval = 5.0

    /// A child that has reported its result has nothing left to do but exit.
    private static let exitGraceSeconds = 30.0

    private struct Progress {
        var lastChange: Date?
        var ending: Ending?
        var endedAt: Date?
        var didTimeOut = false
        var hasExited = false
    }

    private let child: ProcessSpawner.Child
    private let onEvent: @Sendable (ChildEvent) -> Void
    private let watchdogSeconds: Double
    private let beforeReap: @Sendable () -> Void
    private let progress = Mutex(Progress())

    /// `beforeReap` runs while the pid is still reserved, so no one can signal a reused pid.
    init(
        child: ProcessSpawner.Child,
        beforeReap: @escaping @Sendable () -> Void,
        onEvent: @escaping @Sendable (ChildEvent) -> Void
    ) {
        self.child = child
        self.beforeReap = beforeReap
        self.onEvent = onEvent
        let override = ProcessInfo.processInfo.environment["PDF2MD_WATCHDOG_SECONDS"]
        self.watchdogSeconds = override.flatMap(Double.init) ?? Self.defaultWatchdogSeconds
    }

    /// Returns once the child has exited and been reaped.
    func wait() async -> Ending {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: self.readUntilExit())
            }
        }
    }

    private func readUntilExit() -> Ending {
        let timer = startWatchdog()
        defer { timer.cancel() }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: Self.readSize)
        while true {
            let count = read(child.events, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer[..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                handle(line: pending[pending.startIndex..<newline])
                pending = Data(pending[pending.index(after: newline)...])
            }
        }
        close(child.events)
        close(child.control)
        progress.withLock { $0.hasExited = true }
        beforeReap()
        return reap()
    }

    private func handle(line: Data) {
        guard let event = try? JSONDecoder().decode(ChildEvent.self, from: line) else { return }
        progress.withLock { state in
            switch event {
            case .opening, .started, .page:
                state.lastChange = Date()
            case .finished(let report):
                state.ending = .finished(report)
                state.endedAt = Date()
            case .failed(let reason):
                state.ending = .failed(reason)
                state.endedAt = Date()
            }
        }
        onEvent(event)
    }

    private func reap() -> Ending {
        var status: Int32 = 0
        while waitpid(child.pid, &status, 0) < 0, errno == EINTR {}
        return progress.withLock { state in
            if state.didTimeOut { return .hung }
            if let ending = state.ending { return ending }
            // WIFSIGNALED: low seven bits hold the signal, unless they're 0 (exited) or 0x7f.
            let signal = status & 0x7F
            return .crashed(signal: signal != 0 && signal != 0x7F ? signal : nil)
        }
    }

    private func startWatchdog() -> any DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        let interval = min(Self.checkInterval, max(watchdogSeconds / 4, 0.05))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [self] in
            // The kill stays inside the lock, because the pid is only ours until the child exits.
            progress.withLock { state in
                guard !state.hasExited else { return }
                if let endedAt = state.endedAt {
                    if Date().timeIntervalSince(endedAt) > Self.exitGraceSeconds {
                        kill(child.pid, SIGKILL)
                    }
                } else if let last = state.lastChange,
                    Date().timeIntervalSince(last) > watchdogSeconds
                {
                    state.didTimeOut = true
                    kill(child.pid, SIGKILL)
                }
            }
        }
        timer.resume()
        return timer
    }
}

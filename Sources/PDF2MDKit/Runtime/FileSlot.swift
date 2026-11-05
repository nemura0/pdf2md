import Darwin
import Foundation

/// A lock on a slot file. The kernel releases it if the holder dies, so a crash can't leak a
/// permit, and waiters wake immediately without polling (ADR-0007).
public final class FileSlot {
    private let descriptor: Int32

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // O_CLOEXEC: an inherited descriptor would keep the lock alive after its owner is gone.
        let opened = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard opened >= 0 else {
            throw ConversionFailure("couldn't open \(url.lastPathComponent): \(Self.errorText())")
        }
        self.descriptor = opened
    }

    deinit {
        close(descriptor)
    }

    /// Blocks until the slot is free. Call this on a thread that is allowed to block.
    public func lockExclusively() {
        lock(LOCK_EX)
    }

    public func lockShared() {
        lock(LOCK_SH)
    }

    public func tryLockExclusively() -> Bool {
        flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }

    public func unlock() {
        flock(descriptor, LOCK_UN)
    }

    private func lock(_ operation: Int32) {
        while flock(descriptor, operation) != 0, errno == EINTR {}
    }

    private static func errorText() -> String {
        String(cString: strerror(errno))
    }
}

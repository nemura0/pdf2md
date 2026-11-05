import Darwin
import Foundation

/// Spawns this executable again, for per-file children and for `--detach`.
public enum ProcessSpawner {
    struct Child {
        let pid: pid_t
        let events: Int32
        let control: Int32
    }

    static func executablePath() throws -> String {
        var size: UInt32 = 4096
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            throw ConversionFailure("couldn't find the running executable")
        }
        guard let resolved = realpath(buffer, nil) else {
            throw ConversionFailure("couldn't find the running executable")
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// stdin is a control pipe (EOF means the supervisor is gone), stdout carries JSON events, and
    /// stderr goes nowhere, since PDFKit logs noise there.
    static func spawnChild(arguments: [String]) throws -> Child {
        let control = try makePipe()
        let events = try makePipe()
        var didSpawn = false
        defer {
            if !didSpawn {
                [control.read, control.write, events.read, events.write].forEach { close($0) }
            }
        }
        var actions = try makeActions()
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, control.read, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, events.write, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        let pid = try spawn(arguments: arguments, actions: &actions, flags: 0)
        didSpawn = true
        close(control.read)
        close(events.write)
        return Child(pid: pid, events: events.read, control: control.write)
    }

    /// Starts this executable again in its own session, so it outlives the Quick Action, with
    /// nothing inherited but a pipe at `readyDescriptor`. The new process writes a byte there when
    /// its job is registered, so an immediate `--cancel` can't miss it. If it dies first, this
    /// throws. If it's merely slow, as on a stuck volume, this returns after a while and it goes on.
    public static func spawnDetached(
        executable: String? = nil,
        arguments: [String],
        readyDescriptor: Int32
    ) throws {
        let ready = try makePipe()
        defer { close(ready.read) }
        var actions = try makeActions()
        defer { posix_spawn_file_actions_destroy(&actions) }
        // First, since with stdio closed in this process the pipe can be descriptor 0, 1 or 2.
        posix_spawn_file_actions_adddup2(&actions, ready.write, readyDescriptor)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        do {
            _ = try spawn(
                executable: executable,
                arguments: arguments,
                actions: &actions,
                flags: Int32(POSIX_SPAWN_SETSID)
            )
        } catch {
            close(ready.write)
            throw error
        }
        close(ready.write)
        guard try waitForReadiness(on: ready.read) else {
            throw ConversionFailure("the background job couldn't start")
        }
    }

    /// False if the pipe closed without a byte, which means the process died.
    private static func waitForReadiness(on descriptor: Int32) throws -> Bool {
        var request = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        while true {
            let count = poll(&request, 1, detachTimeoutMilliseconds)
            if count == 0 { return true }
            if count > 0 { break }
            if errno != EINTR { throw ConversionFailure("couldn't wait for the background job") }
        }
        var byte: UInt8 = 0
        while true {
            let count = read(descriptor, &byte, 1)
            if count >= 0 { return count == 1 }
            if errno != EINTR { return false }
        }
    }

    /// Finder is waiting on the Quick Action, and registering normally takes milliseconds.
    private static let detachTimeoutMilliseconds: Int32 = 30_000

    private static func spawn(
        executable: String? = nil,
        arguments: [String],
        actions: inout posix_spawn_file_actions_t?,
        flags: Int32
    ) throws -> pid_t {
        let executable = try executable ?? executablePath()
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // CLOEXEC_DEFAULT: an inherited descriptor would keep a flock or a pipe alive for as long
        // as this child runs. SETSIGDEF: the supervisor ignores signals to handle them itself, and
        // ignored signals survive exec.
        let allFlags = Int32(POSIX_SPAWN_CLOEXEC_DEFAULT) | Int32(POSIX_SPAWN_SETSIGDEF) | flags
        posix_spawnattr_setflags(&attributes, Int16(allFlags))
        var signals = sigset_t()
        sigfillset(&signals)
        posix_spawnattr_setsigdefault(&attributes, &signals)

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
        guard status == 0 else {
            throw ConversionFailure("couldn't start a worker: \(String(cString: strerror(status)))")
        }
        return pid
    }

    private static func makeActions() throws -> posix_spawn_file_actions_t? {
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            throw ConversionFailure("couldn't start a worker")
        }
        return actions
    }

    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else {
            throw ConversionFailure("couldn't start a worker: \(String(cString: strerror(errno)))")
        }
        return (descriptors[0], descriptors[1])
    }
}

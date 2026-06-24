import Darwin
import Foundation

/// A long-running subprocess whose stdout is delivered line-by-line as it
/// arrives (never buffered to completion). It is spawned as a process-group
/// leader (`POSIX_SPAWN_SETPGROUP`) so the whole tree — `claude` plus the MCP
/// node/npx children — can be killed together with `killpg`.
public final class StreamingProcess: @unchecked Sendable {
    private let executablePath: String
    private let arguments: [String]

    private var pid: pid_t = -1
    private let outRead: Int32
    private let outWrite: Int32
    private let errRead: Int32
    private let errWrite: Int32

    private let lock = NSLock()
    private var buffer = Data()
    private var errBuffer = Data()
    private var errTail: [String] = []   // last N stderr lines (ring buffer)
    private let errTailCap = 10
    private static let errLineCap = 2_000   // per-line char cap to bound memory
    private var started = false
    private var exited = false

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
        var outFds: [Int32] = [0, 0]
        var errFds: [Int32] = [0, 0]
        pipe(&outFds)
        pipe(&errFds)
        outRead = outFds[0]; outWrite = outFds[1]
        errRead = errFds[0]; errWrite = errFds[1]
    }

    /// Start the process. `onLine` fires for each complete stdout line;
    /// `onExit` fires once with the exit code after the process ends.
    /// `onExit` fires once with the exit code and a diagnostic message. On a
    /// non-zero/abnormal exit the message includes the last few stderr lines so
    /// a failed run (e.g. "MCP server failed to start") is diagnosable. stderr
    /// here is process diagnostics only — no secrets are emitted.
    public func start(onLine: @escaping @Sendable (String) -> Void,
                      onExit: @escaping @Sendable (Int32, String) -> Void) throws {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, outWrite, 1)
        posix_spawn_file_actions_adddup2(&fileActions, errWrite, 2)
        posix_spawn_file_actions_addclose(&fileActions, outRead)
        posix_spawn_file_actions_addclose(&fileActions, errRead)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        // New process group (leader = child pid) so killpg reaps the whole tree.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)
        defer { posix_spawnattr_destroy(&attr) }

        // argv[0] = executable path.
        let argv = ([executablePath] + arguments).map { strdup($0) } + [nil]
        defer { for ptr in argv where ptr != nil { free(ptr) } }

        var childPID: pid_t = 0
        let rc = posix_spawn(&childPID, executablePath, &fileActions, &attr, argv, environ)
        // Parent closes the write ends.
        close(outWrite); close(errWrite)
        guard rc == 0 else {
            close(outRead); close(errRead)
            throw ShellError.toolNotFound(executablePath)
        }
        pid = childPID

        let outHandle = FileHandle(fileDescriptor: outRead, closeOnDealloc: true)
        let errHandle = FileHandle(fileDescriptor: errRead, closeOnDealloc: true)

        outHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.flushRemaining(onLine: onLine)
                return
            }
            self.lock.lock()
            self.buffer.append(chunk)
            let lines = self.extractLines()
            self.lock.unlock()
            for line in lines { onLine(line) }
        }
        errHandle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            self.appendStderr(chunk)
        }

        // Reap the child on a background thread and report its exit code.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            waitpid(childPID, &status, 0)
            let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
            self?.markExited()
            let reason = self?.exitReason(code: code) ?? ""
            onExit(code, reason)
        }
    }

    private func appendStderr(_ chunk: Data) {
        lock.lock()
        errBuffer.append(chunk)
        let newline = UInt8(ascii: "\n")
        while let idx = errBuffer.firstIndex(of: newline) {
            let lineData = errBuffer[errBuffer.startIndex..<idx]
            errBuffer.removeSubrange(errBuffer.startIndex...idx)
            recordErrLine(lineData)
        }
        // Bound the in-flight (no-newline-yet) buffer too.
        if errBuffer.count > Self.errLineCap * 4 {
            errBuffer.removeSubrange(errBuffer.startIndex..<errBuffer.index(errBuffer.endIndex, offsetBy: -Self.errLineCap))
        }
        lock.unlock()
    }

    /// Caller must hold `lock`.
    private func recordErrLine(_ data: Data) {
        guard var s = String(data: data, encoding: .utf8) else { return }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if s.count > Self.errLineCap { s = String(s.prefix(Self.errLineCap)) + "…" }
        errTail.append(s)
        if errTail.count > errTailCap { errTail.removeFirst(errTail.count - errTailCap) }
    }

    /// Snapshot of the last few stderr lines captured from the child.
    public func stderrTail() -> [String] {
        lock.lock(); defer { lock.unlock() }
        // Include any trailing partial line that never got a newline.
        var tail = errTail
        if let s = String(data: errBuffer, encoding: .utf8) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { tail.append(t.count > Self.errLineCap ? String(t.prefix(Self.errLineCap)) + "…" : t) }
        }
        return Array(tail.suffix(errTailCap))
    }

    private func exitReason(code: Int32) -> String {
        if code == 0 { return "exited cleanly" }
        let tail = stderrTail()
        var msg = code < 0 ? "terminated abnormally" : "exited with code \(code)"
        if !tail.isEmpty {
            msg += "; last stderr:\n" + tail.joined(separator: "\n")
        }
        return msg
    }

    private func markExited() {
        lock.lock(); exited = true; lock.unlock()
    }

    private func extractLines() -> [String] {
        var lines: [String] = []
        let newline = UInt8(ascii: "\n")
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            if let s = String(data: lineData, encoding: .utf8) { lines.append(s) }
        }
        return lines
    }

    private func flushRemaining(onLine: @escaping @Sendable (String) -> Void) {
        lock.lock()
        let remaining = buffer
        buffer.removeAll()
        lock.unlock()
        if !remaining.isEmpty, let s = String(data: remaining, encoding: .utf8),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onLine(s)
        }
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return started && !exited
    }

    /// SIGTERM the process group, then SIGKILL after a grace period.
    public func stop() {
        lock.lock()
        let alive = started && !exited
        let target = pid
        lock.unlock()
        guard alive, target > 0 else { return }
        killpg(target, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isRunning else { return }
            killpg(target, SIGKILL)
        }
    }
}

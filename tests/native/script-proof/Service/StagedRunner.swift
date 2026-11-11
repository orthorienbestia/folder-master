import Foundation
import Darwin

// A bounded feasibility runner, not the product executor. Full quota enforcement,
// descendant escape probes and release client authentication remain M1 gates.
enum StagedRunner {
    static let outputLimit = 4 * 1024 * 1024
    static let logLimit = 64 * 1024

    static func execute(_ encoded: Data) -> ScriptProofReply {
        do {
            guard encoded.count <= 2 * 1024 * 1024 else { throw failure("Oversized request") }
            let request = try JSONDecoder().decode(ScriptProofRequest.self, from: encoded)
            guard request.version == 1, request.script.count <= 65536,
                  !request.script.isEmpty, !request.script.contains(0),
                  request.input.count <= 1024 * 1024, request.metadata.count <= 65536,
                  request.arguments.count <= 32, (1...30).contains(request.timeoutSeconds),
                  request.arguments.allSatisfy({ $0.utf8.count <= 4096 && !$0.contains("\0") }) else { throw failure("Invalid request bounds") }
            guard String(data: request.script, encoding: .utf8) != nil,
                  (try JSONSerialization.jsonObject(with: request.metadata)) is [String:Any] else { throw failure("Invalid script or metadata") }
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("script-proof-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
            defer { try? fm.removeItem(at: root) }
            let output = root.appendingPathComponent("output", isDirectory: true)
            let temporary = root.appendingPathComponent("tmp", isDirectory: true)
            for directory in [output, temporary] { try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700]) }
            let script = root.appendingPathComponent("script.zsh")
            let input = root.appendingPathComponent("input.bin")
            let metadata = root.appendingPathComponent("metadata.json")
            for (url, data) in [(script, request.script), (input, request.input), (metadata, request.metadata)] {
                try data.write(to: url, options: .withoutOverwriting)
                try fm.setAttributes([.posixPermissions:0o400], ofItemAtPath: url.path)
            }
            let outputFD = open(output.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard outputFD >= 0 else { throw posixFailure() }
            defer { close(outputFD) }
            let result = try run(script: script, input: input, metadata: metadata, root: root, output: output, temporary: temporary, request: request)
            guard !result.timedOut else { return ScriptProofReply(status: "timed_out", message: "Execution deadline reached", exitCode: nil, log: result.log, outputs: []) }
            guard !result.logExceeded else { return ScriptProofReply(status: "limit_exceeded", message: "Log limit reached", exitCode: nil, log: result.log, outputs: []) }
            guard result.exitCode == 0 else { return ScriptProofReply(status: "failed", message: "Script exited unsuccessfully", exitCode: result.exitCode, log: result.log, outputs: []) }
            let outputs = try collectOutputs(directoryFD: outputFD)
            return ScriptProofReply(status: "succeeded", message: "Staged execution completed", exitCode: 0, log: result.log, outputs: outputs)
        } catch {
            return ScriptProofReply(status: "rejected", message: error.localizedDescription, exitCode: nil, log: Data(), outputs: [])
        }
    }

    private struct ProcessResult {
        let exitCode: Int32?
        let timedOut: Bool
        let logExceeded: Bool
        let log: Data
    }
    private static func run(script: URL, input: URL, metadata: URL, root: URL, output: URL, temporary: URL, request: ScriptProofRequest) throws -> ProcessResult {
        var pipeFDs: [Int32] = [0,0]
        guard pipe(&pipeFDs) == 0 else { throw posixFailure() }
        defer { close(pipeFDs[0]) }
        var writeOpen = true
        defer { if writeOpen { close(pipeFDs[1]) } }
        guard fcntl(pipeFDs[0], F_SETFL, O_NONBLOCK) == 0 else { throw posixFailure() }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, pipeFDs[1], STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, pipeFDs[1], STDERR_FILENO))
        if #available(macOS 26.0, *) { try check(posix_spawn_file_actions_addchdir(&actions, root.path)) }
        else { try check(posix_spawn_file_actions_addchdir_np(&actions, root.path)) }
        let argv = ["/bin/zsh", "-f", "--", script.path, input.path, metadata.path, output.path] + request.arguments
        let environment = ["PATH=/usr/bin:/bin", "HOME=\(root.path)", "TMPDIR=\(temporary.path)", "LANG=C", "LC_ALL=C", "TZ=UTC"]
        var arguments = argv.map { strdup($0) } + [nil]
        var env = environment.map { strdup($0) } + [nil]
        defer { for pointer in arguments { free(pointer) }; for pointer in env { free(pointer) } }
        guard !arguments.dropLast().contains(where: { $0 == nil }), !env.dropLast().contains(where: { $0 == nil }) else { throw failure("Argument allocation failed") }
        var pid: pid_t = 0
        let status = arguments.withUnsafeMutableBufferPointer { argumentBuffer in
            env.withUnsafeMutableBufferPointer { environmentBuffer in
                posix_spawn(&pid, "/bin/zsh", &actions, &attributes, argumentBuffer.baseAddress!, environmentBuffer.baseAddress!)
            }
        }
        try check(status)
        close(pipeFDs[1]); writeOpen = false
        var reaped = false
        defer {
            if !reaped { kill(-pid, SIGKILL); var status: Int32 = 0; while waitpid(pid, &status, 0) < 0 && errno == EINTR {} }
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(request.timeoutSeconds) * 1_000_000_000
        var log = Data()
        var exceeded = false
        func drain() throws {
            var bytes = [UInt8](repeating: 0, count: 8192)
            while true {
                let count = read(pipeFDs[0], &bytes, bytes.count)
                if count > 0 {
                    let allowed = min(count, max(0, logLimit - log.count))
                    log.append(contentsOf: bytes.prefix(allowed))
                    if allowed < count { exceeded = true; return }
                } else if count == 0 || errno == EAGAIN { return }
                else if errno != EINTR { throw posixFailure() }
            }
        }
        var timedOut = false
        while true {
            try drain()
            var info = siginfo_t()
            if waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) != 0 { throw posixFailure() }
            if info.si_pid == pid || exceeded { break }
            if DispatchTime.now().uptimeNanoseconds >= deadline { timedOut = true; break }
            usleep(10_000)
        }
        // Signal the group before reaping its leader, so its ID cannot be
        // reused during cleanup. Escaped-session descendants are a later gate.
        kill(-pid, SIGKILL)
        var terminal: Int32 = 0
        while waitpid(pid, &terminal, 0) < 0 {
            if errno != EINTR { throw posixFailure() }
        }
        reaped = true
        try drain()
        let code: Int32? = terminal & 0x7f == 0 ? (terminal >> 8) & 0xff : nil
        return ProcessResult(exitCode: code, timedOut: timedOut, logExceeded: exceeded, log: log)
    }

    private static func collectOutputs(directoryFD: Int32) throws -> [ScriptProofOutput] {
        let listingFD = openat(directoryFD, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard listingFD >= 0 else { throw posixFailure() }
        guard let listing = fdopendir(listingFD) else { close(listingFD); throw posixFailure() }
        defer { closedir(listing) }
        var outputs: [ScriptProofOutput] = []
        var total = 0
        while true {
            errno = 0
            guard let entry = readdir(listing) else {
                if errno != 0 { throw posixFailure() }; break
            }
            let raw = withUnsafeBytes(of: entry.pointee.d_name) { Data($0.prefix(Int(entry.pointee.d_namlen))) }
            guard let name = String(data: raw, encoding: .utf8) else { throw failure("Unsupported output name") }
            if name == "." || name == ".." { continue }
            guard outputs.count < 32, !name.isEmpty, !name.contains("/"), !name.contains("\0") else { throw failure("Output manifest limit or invalid name") }
            let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard fd >= 0 else { throw posixFailure() }
            let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? file.close() }
            var before = stat()
            guard fstat(fd, &before) == 0 else { throw posixFailure() }
            guard before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
                  before.st_size >= 0, before.st_size <= outputLimit - total else { throw failure("Only bounded independent regular outputs are allowed") }
            let bytes = try file.read(upToCount: outputLimit - total + 1) ?? Data()
            var after = stat()
            guard fstat(fd, &after) == 0 else { throw posixFailure() }
            guard bytes.count == before.st_size, bytes.count <= outputLimit - total,
                  before.st_size == after.st_size, after.st_nlink == 1,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw failure("Output changed during validation") }
            total += bytes.count
            outputs.append(ScriptProofOutput(name: name, bytes: bytes))
        }
        return outputs.sorted { $0.name < $1.name }
    }
    private static func failure(_ message: String) -> NSError { ProofSigning.failure(message) }
    private static func posixFailure() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    private static func check(_ value: Int32) throws { if value != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(value)) } }
}

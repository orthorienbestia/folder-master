import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProofSigning.failure(message) }
}

func runProof() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("folder-master-script-original-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
    defer { try? fm.removeItem(at: root) }
    let original = root.appendingPathComponent("original.txt")
    let originalBytes = Data("ORIGINAL MUST STAY LOCAL AND UNCHANGED\n".utf8)
    try originalBytes.write(to: original)
    let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/ScriptProofService.xpc")
    let connection = NSXPCConnection(serviceName: "local.foldermaster.script-proof.service")
    connection.remoteObjectInterface = NSXPCInterface(with: ScriptProofProtocol.self)
    connection.setCodeSigningRequirement(try ProofSigning.requirement(at: helper))
    connection.activate()
    defer { connection.invalidate() }

    // The original path is supplied only as a denial probe, never as an input
    // path intended for mutation. Actual script input arrives as staged bytes.
    let script = """
    set -eu
    /bin/cat -- "$1" > "$3/result.txt"
    /usr/bin/printf '%s' "$5" > "$3/argument.txt"
    if /bin/cat -- "$4" >/dev/null 2>&1; then
        /usr/bin/printf 'ORIGINAL_READ_ALLOWED' >&2; exit 81
    fi
    if /usr/bin/printf 'changed' > "$4" 2>/dev/null; then
        /usr/bin/printf 'ORIGINAL_WRITE_ALLOWED' >&2; exit 82
    fi
    /usr/bin/printf 'staged script completed'
    """
    let literal = "literal argument ; $(touch SHOULD_NOT_EXIST)"
    let job = ScriptProofRequest(version: 1, script: Data(script.utf8), input: Data("STAGED INPUT\n".utf8), metadata: Data("{\"fixture\":true}".utf8), arguments: [original.path, literal], timeoutSeconds: 10)
    let reply = try send(job, connection: connection)
    try require(reply.status == "succeeded", "Service failed: \(reply.status): \(reply.message)")
    try require(reply.exitCode == 0, "Script did not exit successfully")
    try require(reply.outputs.count == 2, "Unexpected output manifest")
    var outputs: [String:Data] = [:]
    var total = 0
    for item in reply.outputs {
        try require(!item.name.isEmpty && item.name != "." && item.name != ".." && !item.name.contains("/") && !item.name.contains("\0"), "Unsafe returned output name")
        try require(outputs[item.name] == nil, "Duplicate output name")
        total += item.bytes.count
        try require(total <= 4 * 1024 * 1024, "Oversized returned outputs")
        outputs[item.name] = item.bytes
    }
    try require(outputs["result.txt"] == Data("STAGED INPUT\n".utf8), "Staged input output mismatch")
    try require(outputs["argument.txt"] == Data(literal.utf8), "Literal argv was evaluated or altered")
    try require(reply.log.contains(Data("staged script completed".utf8)), "Completion log missing")
    let after = try Data(contentsOf: original)
    try require(after == originalBytes, "Original was changed")
    print("Script XPC proof passed: signed peer, staged zsh input, literal argv, validated outputs, original read/write denied")

    let invalid = ScriptProofRequest(version: 2, script: Data("exit 0".utf8), input: Data(), metadata: Data("{}".utf8), arguments: [], timeoutSeconds: 2)
    let invalidReply = try send(invalid, connection: connection)
    try require(invalidReply.status == "rejected", "Future request schema was executed")
    let malformed = try sendEncoded(Data("{".utf8), connection: connection)
    try require(malformed.status == "rejected", "Malformed request was accepted")
    for (name, script, expected, timeout) in [
        ("symlink output", "/bin/ln -s -- \"$1\" \"$3/link\"", "rejected", 2),
        ("hard-link output", "/bin/ln -- \"$1\" \"$3/link\"", "rejected", 2),
        ("oversized output", "/bin/dd if=/dev/zero of=\"$3/large\" bs=1048576 count=5 2>/dev/null", "rejected", 2),
        ("failed script", "/usr/bin/printf partial > \"$3/partial\"; exit 9", "failed", 2),
        ("log limit", "printf '%070000d' 0", "limit_exceeded", 2),
        ("timeout", "/bin/sleep 5 & wait", "timed_out", 1)
    ] {
        let test = ScriptProofRequest(version: 1, script: Data(script.utf8), input: Data("staged".utf8), metadata: Data("{}".utf8), arguments: [], timeoutSeconds: timeout)
        let started = DispatchTime.now().uptimeNanoseconds
        let actual = try send(test, connection: connection)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        try require(actual.status == expected, "\(name): expected \(expected), got \(actual.status): \(actual.message)")
        try require(actual.outputs.isEmpty && actual.log.count <= 65536, "\(name): unsafe or over-limit result returned")
        if name == "timeout" { try require(elapsed < 4, "Timeout did not stop the current script promptly") }
        print("Script proof passed: \(name) (\(String(format: "%.2f", elapsed))s)")
    }

    if CommandLine.arguments.contains("--isolation") {
        let (server, port) = try IsolationProbe.listener()
        defer { close(server) }
        let probeExecutable = helper.appendingPathComponent("Contents/Helpers/ScriptIsolationProbe")
        let controlProcess = Process()
        let controlOutput = Pipe()
        controlProcess.executableURL = probeExecutable
        controlProcess.arguments = [String(port)]
        controlProcess.standardOutput = controlOutput
        try controlProcess.run()
        let controlData = controlOutput.fileHandleForReading.readDataToEndOfFile()
        controlProcess.waitUntilExit()
        try require(controlProcess.terminationStatus == 0, "Unentitled probe control did not exit successfully")
        guard let control = try JSONSerialization.jsonObject(with: controlData) as? [String:Int32] else { throw ProofSigning.failure("Invalid control response") }
        try require(control["network_errno"] == 0 && control["launchservices_lookup"] == 0, "Unsandboxed control could not reach local listener and Launch Services")
        print("Unentitled probe control observed: \(control)")
        let probeScript = "\"$4\" \"$5\" > \"$3/probe.json\""
        let probeJob = ScriptProofRequest(version: 1, script: Data(probeScript.utf8), input: Data(), metadata: Data("{}".utf8), arguments: [probeExecutable.path,String(port)], timeoutSeconds: 10)
        let probeReply = try send(probeJob, connection: connection)
        try require(probeReply.status == "succeeded", "Child isolation probe did not complete: \(probeReply.status): \(String(decoding: probeReply.log, as: UTF8.self))")
        guard let bytes = probeReply.outputs.first(where: { $0.name == "probe.json" })?.bytes,
              let values = try JSONSerialization.jsonObject(with: bytes) as? [String:Int32] else { throw ProofSigning.failure("Invalid isolation probe response") }
        print("Child isolation observed: \(values)")
        try require(values["network_errno"] == EPERM || values["network_errno"] == EACCES, "Child networking was not denied by sandbox")
        try require(values["launchservices_lookup"] != 0, "Unsafe Launch Services IPC remains available; do not enable product scripts")
        print("Child network and Launch Services IPC denial probes passed")
    }
}

func send(_ job: ScriptProofRequest, connection: NSXPCConnection) throws -> ScriptProofReply {
    try sendEncoded(JSONEncoder().encode(job), connection: connection)
}

func sendEncoded(_ request: Data, connection: NSXPCConnection) throws -> ScriptProofReply {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var response: Result<Data, Error>?
    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        lock.lock(); response = .failure(error); lock.unlock(); semaphore.signal()
    }) as? ScriptProofProtocol else { throw ProofSigning.failure("Missing service proxy") }
    proxy.execute(request) { data in
        lock.lock(); response = .success(data); lock.unlock(); semaphore.signal()
    }
    try require(semaphore.wait(timeout: .now() + 20) == .success, "XPC proof timed out; no fallback was executed")
    lock.lock(); let result = response; lock.unlock()
    guard let result else { throw ProofSigning.failure("Missing XPC result") }
    return try JSONDecoder().decode(ScriptProofReply.self, from: result.get())
}

do { try runProof() }
catch { FileHandle.standardError.write(Data("Script XPC proof failed: \(error as NSError)\n".utf8)); exit(1) }

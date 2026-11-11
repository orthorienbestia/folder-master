import Foundation

@main
struct BridgeSmoke {
    static func main() async throws {
        let client = EngineClient()
        let status = try await client.request(op: "status")
        precondition(status.type == "completed" && status.payload.automation_available == false)
        let pause = try await client.request(op: "set_paused", paused: true)
        precondition(pause.payload.paused == true)
        let raw = Data([47, 116, 109, 112, 47, 255, 46, 112, 100, 102])
        let echo = try await client.request(op: "echo_path", path: raw)
        precondition(echo.payload.path_bytes_base64 == "L3RtcC//LnBkZg==")
        // Concurrent native calls must be routed by request ID, never by arrival order.
        async let first = client.request(op: "set_paused", paused: false)
        async let second = client.request(op: "status")
        let replies = try await [first, second]
        precondition(replies.allSatisfy { $0.type == "completed" })
        let rejected = await Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await client.request(op: "set_paused", paused: true)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        guard rejected else {
            FileHandle.standardError.write(Data("Pre-canceled native request was submitted instead of rejected\n".utf8))
            exit(1)
        }
        let unchanged = try await client.request(op: "status")
        precondition(unchanged.payload.paused == false)
        do {
            _ = try await client.request(op: "delete_all")
            fatalError("Unknown command was accepted")
        } catch EngineClientError.status { }
        await client.shutdown()
        do {
            _ = try await client.request(op: "status")
            fatalError("Closed client accepted work")
        } catch EngineClientError.stopped { }
        print("Swift ↔ Rust bridge smoke passed: status, pause, byte paths, correlation, rejection, shutdown")
    }
}

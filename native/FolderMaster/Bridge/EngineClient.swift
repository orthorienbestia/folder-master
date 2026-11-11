import Foundation

struct EnginePayload: Decodable {
    var engine_version: String?
    var paused: Bool?
    var automation_available: Bool?
    var path_bytes_base64: String?
    var code: String?
    var message: String?
    var store_open: Bool?
    var folder_count: Int?
    var folders: [StoredFolder]?
    var folder: StoredFolder?
    var next_offset: Int?
}

struct EngineReply: Decodable {
    var version: Int
    var request_id: String
    var type: String
    var payload: EnginePayload
}

enum EngineClientError: LocalizedError {
    case status(UInt32), protocolMismatch, stopped, timedOut
    case operation(code: String, message: String)
    var errorDescription: String? {
        switch self {
        case .status(let code):
            switch code {
            case 2: return "The local engine session is unavailable. Reopen the app to reconnect."
            case 3: return "The local engine received an invalid or unsupported request."
            case 4: return "The local engine is busy. Try again after pending work finishes."
            case 5: return "This request is already pending. Wait for its result."
            case 6: return "This request is no longer pending."
            case 8: return "The current step has already started and must finish safely."
            default: return "The local engine stopped after an internal error. Reopen the app before continuing."
            }
        case .protocolMismatch: return "The local engine returned an unsupported response."
        case .stopped: return "The local engine has stopped."
        case .timedOut: return "The local engine did not respond in time."
        case .operation(_, let message): return message
        }
    }
}

actor EngineClient {
    private var handle: UInt64 = 0
    private var pending: [String: CheckedContinuation<EngineReply, Error>] = [:]
    private var pump: Task<Void, Never>?
    private var stopped = false

    func openStore(at url: URL) async throws -> EngineReply {
        try await requestCommand(["op":"open_store", "path_bytes_base64":try NativeFolderAccess.pathData(for: url).base64EncodedString()])
    }
    func listFolders() async throws -> [StoredFolder] {
        var result: [StoredFolder] = []
        var offset = 0
        while true {
            let reply = try await requestCommand(["op":"list_folders", "offset":offset])
            guard let folders = reply.payload.folders else { throw EngineClientError.protocolMismatch }
            result.append(contentsOf: folders)
            guard let next = reply.payload.next_offset else { return result }
            guard next > offset else { throw EngineClientError.protocolMismatch }
            offset = next
        }
    }
    func addFolder(_ candidate: FolderCandidate, name: String) async throws -> StoredFolder {
        let reply = try await requestCommand(["op":"add_folder", "id":UUID().uuidString, "name":name,
                                              "path_bytes_base64":candidate.path.base64EncodedString(),
                                              "bookmark_base64":candidate.bookmark.base64EncodedString()])
        guard let folder = reply.payload.folder else { throw EngineClientError.protocolMismatch }
        return folder
    }
    func updateFolder(_ folder: StoredFolder) async throws -> StoredFolder {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(folder))
        let reply = try await requestCommand(["op":"update_folder", "folder":object])
        guard let saved = reply.payload.folder else { throw EngineClientError.protocolMismatch }
        return saved
    }
    func removeFolder(_ folder: StoredFolder) async throws {
        _ = try await requestCommand(["op":"remove_folder", "id":folder.id, "revision":folder.revision])
    }

    func request(op: String, paused: Bool? = nil, path: Data? = nil) async throws -> EngineReply {
        var command: [String: Any] = ["op": op]
        if let paused { command["paused"] = paused }
        if let path { command["path_bytes_base64"] = path.base64EncodedString() }
        return try await requestCommand(command)
    }

    private func requestCommand(_ command: [String: Any]) async throws -> EngineReply {
        try Task.checkCancellation()
        if stopped { throw EngineClientError.stopped }
        if handle == 0 {
            let created = fm_engine_create()
            guard created.status == FM_OK else { throw EngineClientError.status(created.status.rawValue) }
            handle = created.handle
        }
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "request_id": id, "command": command])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let status = data.withUnsafeBytes { bytes in
                    fm_engine_submit(handle, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
                }
                guard status == FM_OK else {
                    continuation.resume(throwing: EngineClientError.status(status.rawValue))
                    return
                }
                pending[id] = continuation
                if pump == nil { pump = Task { await self.drain() } }
            }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    private func cancelRequest(_ id: String) {
        guard pending[id] != nil else { return }
        let bytes = Data(id.utf8)
        let status = bytes.withUnsafeBytes { data in
            fm_engine_cancel(handle, data.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
        switch status {
        case FM_OK, FM_TOO_LATE, FM_NOT_FOUND:
            // Keep waiting for the actual terminal event. A step that already
            // started may complete; cancellation never implies rollback.
            break
        default: failAll(EngineClientError.status(status.rawValue))
        }
    }

    private func drain() async {
        let deadline = Date().addingTimeInterval(5)
        while !pending.isEmpty && !Task.isCancelled {
            let result = fm_engine_poll(handle)
            if result.status == FM_OK {
                defer { _ = fm_buffer_release(result.allocation) }
                do {
                    let data: Data
                    if let bytes = result.data { data = Data(bytes: bytes, count: result.len) }
                    else { throw EngineClientError.protocolMismatch }
                    let reply = try JSONDecoder().decode(EngineReply.self, from: data)
                    guard reply.version == 1 else { throw EngineClientError.protocolMismatch }
                    guard let continuation = pending.removeValue(forKey: reply.request_id) else { continue }
                    switch reply.type {
                    case "completed": continuation.resume(returning: reply)
                    case "canceled": continuation.resume(throwing: CancellationError())
                    case "error": continuation.resume(throwing: EngineClientError.operation(code: reply.payload.code ?? "engine_error", message: reply.payload.message ?? "The local engine could not finish this request."))
                    default: continuation.resume(throwing: EngineClientError.protocolMismatch)
                    }
                } catch { failAll(error) }
            } else if result.status != FM_EMPTY {
                failAll(EngineClientError.status(result.status.rawValue))
            } else if Date() > deadline {
                failAll(EngineClientError.timedOut)
                _ = fm_engine_destroy(handle)
                handle = 0
            } else {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        pump = nil
    }

    private func failAll(_ error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
    }

    func shutdown() {
        stopped = true
        pump?.cancel()
        pump = nil
        failAll(EngineClientError.stopped)
        if handle != 0 { _ = fm_engine_destroy(handle); handle = 0 }
    }
}

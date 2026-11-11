import Foundation

@main
struct PersistentStoreSmoke {
    static func main() async {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("folder-master-native-store-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
            try fm.createDirectory(at: inbox, withIntermediateDirectories: false)
            try Data("original".utf8).write(to: inbox.appendingPathComponent("original.txt"))
            let candidate = try NativeFolderAccess.candidate(for: inbox)
            let dataRoot = root.appendingPathComponent("data", isDirectory: true)
            let first = EngineClient()
            let opened = try await first.openStore(at: dataRoot)
            guard opened.payload.store_open == true else { throw Failure.check("Store did not open") }
            var folder = try await first.addFolder(candidate, name: "Inbox")
            guard !folder.enabled, folder.revision == 1 else { throw Failure.check("Unsafe enrollment defaults") }
            folder.display_name = "Receipts"; folder.recursive = true
            let saved = try await first.updateFolder(folder)
            guard saved.revision == 2 else { throw Failure.check("Update was not revisioned") }
            let paused = try await first.request(op: "set_paused", paused: false)
            guard paused.payload.paused == false else { throw Failure.check("Pause did not persist") }
            let second = EngineClient()
            do {
                _ = try await second.openStore(at: dataRoot)
                throw Failure.check("Second native engine acquired an owned store")
            } catch let error as EngineClientError {
                guard error.localizedDescription.contains("Another Folder Master") else { throw error }
            }
            await first.shutdown()
            _ = try await second.openStore(at: dataRoot)
            let loaded = try await second.listFolders()
            guard loaded.count == 1, loaded[0].display_name == "Receipts", loaded[0].recursive else { throw Failure.check("Native reopen lost folder state") }
            let status = try await second.request(op: "status")
            guard status.payload.paused == false else { throw Failure.check("Native reopen lost pause state") }
            try await second.removeFolder(loaded[0])
            guard try await second.listFolders().isEmpty else { throw Failure.check("Configuration removal failed") }
            guard try Data(contentsOf: inbox.appendingPathComponent("original.txt")) == Data("original".utf8) else { throw Failure.check("Original file changed") }
            await second.shutdown()
            try fm.removeItem(at: root)
            print("Native persistence smoke passed: enroll, save, reopen, exclusive owner, pause, remove config; original untouched")
        } catch {
            FileHandle.standardError.write(Data(("Native persistence smoke failed: \(error)\n").utf8))
            exit(1)
        }
    }
    enum Failure: Error { case check(String) }
}

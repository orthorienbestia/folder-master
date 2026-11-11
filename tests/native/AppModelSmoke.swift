import Foundation

@main
struct AppModelSmoke {
    @MainActor static func main() async {
        for shouldSave in [true, false] {
            let model = AppModel()
            model.exploreDemo()
            let originalID = model.selectedRuleID
            model.draft?.name = "Edited invoice rule"
            guard model.dirty else { fail("Editing did not become dirty") }
            model.selectRule(originalID)
            guard model.dirty, model.draft?.name == "Edited invoice rule" else {
                fail("Reselecting the current rule discarded unsaved edits")
            }
            model.addRule()
            guard model.showUnsaved else { fail("New Rule discarded dirty edits without prompting") }
            model.resolveUnsaved(save: shouldSave)
            guard model.experience.rules.count == 4 else { fail("Resolving edits lost the requested New Rule action") }
            guard model.selectedRuleID != originalID, model.draft?.name == "Untitled Rule", model.draft?.enabled == false else {
                fail("New Rule did not select an independent disabled draft")
            }
            guard model.experience.rules[0].name == (shouldSave ? "Edited invoice rule" : "File invoices") else {
                fail("Save/Discard did not preserve the requested edit behavior")
            }
        }
        let pending = AppModel()
        let a = StoredFolder(id: "a", display_name: "A", path_bytes_base64: "L3RtcC9h", bookmark_base64: "", identity: "1:1", enabled: false, recursive: false, include_hidden: false, exclusions: [], watch_mode: "automatic", poll_interval_seconds: 30, revision: 1)
        var b = a; b.id = "b"; b.display_name = "B"
        pending.storedFolders = [a,b]
        pending.selectLiveFolder("a")
        pending.liveDraft?.display_name = "Unsaved A"
        pending.folderPending = true
        pending.selectLiveFolder("b")
        await pending.resolveLiveUnsaved(save: false)
        pending.exploreDemo()
        guard pending.selectedLiveFolderID == "a", pending.liveDraft?.display_name == "Unsaved A", !pending.demo else {
            fail("Pending save allowed navigation to replace the selected folder/draft")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-master-model-retry-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
            let model = AppModel()
            _ = try await model.engine.openStore(at: root.appendingPathComponent("data", isDirectory: true))
            await model.connect()
            guard model.workspaceReady else { fail("Retry could not resume an already-open store: \(model.error ?? "unknown")") }
            await model.shutdown()
            try FileManager.default.removeItem(at: root)
        } catch { fail("Initialization retry test failed: \(error)") }
        for (decision, stale) in [(QuitDecision.cancel, false), (.discard, false), (.save, false), (.save, true)] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-master-quit-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions:0o700])
                let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
                try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: false)
                let model = AppModel()
                _ = try await model.engine.openStore(at: root.appendingPathComponent("data", isDirectory: true))
                await model.connect()
                model.folderCandidate = try NativeFolderAccess.candidate(for: inbox)
                guard await model.addLiveFolder(name: "Original") else { fail("Could not enroll quit fixture") }
                model.liveDraft?.display_name = "Edited before quit"
                if stale {
                    var newer = try await model.engine.listFolders()[0]
                    newer.display_name = "Changed elsewhere"
                    _ = try await model.engine.updateFolder(newer)
                }
                var prompted = false
                let ready = await model.prepareForQuit { prompted = true; return decision }
                guard prompted else { fail("Quit discarded dirty folder configuration without prompting") }
                guard ready == (decision != .cancel && !stale), model.quitPending == ready else { fail("Quit choice did not control termination state") }
                let saved = try await model.engine.listFolders()
                let expected = stale ? "Changed elsewhere" : decision == .save ? "Edited before quit" : "Original"
                guard saved.first?.display_name == expected else { fail("Quit Save/Discard did not persist the chosen configuration") }
                if stale { guard model.liveDirty && model.error != nil else { fail("Failed Quit Save lost draft or error") } }
                if decision == .cancel { guard model.liveDirty else { fail("Cancel Quit discarded the draft") } }
                if decision == .cancel {
                    let selected = model.selectedLiveFolderID
                    model.folderPending = true
                    let release = Task { @MainActor in
                        guard model.quitPending else { fail("Quit did not wait for pending update") }
                        model.folderPending = false
                        model.selectLiveFolder(nil); model.exploreDemo(); model.setPaused(false)
                        guard model.selectedLiveFolderID == selected, !model.demo, !model.showLiveUnsaved, !model.enginePending else { fail("New commands entered during quit preparation") }
                    }
                    let second = await model.prepareForQuit {
                        guard !model.folderPending else { fail("Quit prompted before pending update settled") }
                        return .cancel
                    }
                    await release.value
                    guard !second && !model.quitPending else { fail("Cancel did not release drained quit state") }
                }
                await model.shutdown()
                try FileManager.default.removeItem(at: root)
            } catch { fail("Quit workflow test failed: \(error)") }
        }
        print("Native presentation smoke passed: draft navigation, retry, Quit choices, failed save and pending-update drain")
    }
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

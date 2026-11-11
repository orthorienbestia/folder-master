import Foundation

@main
struct AppModelSmoke {
    @MainActor static func main() async {
        let confirmation = AppModel()
        confirmation.exploreDemo()
        confirmation.presentPreview()
        confirmation.simulateRun()
        guard confirmation.previewPhase == .review, confirmation.activities.isEmpty else {
            fail("Preview started a sample run without confirming its selected file chains")
        }
        confirmation.presentPreview(source: .draft)
        confirmation.requestSimulation(); confirmation.simulateRun()
        guard !confirmation.showRunConfirmation, confirmation.previewPhase == .review else { fail("Test Draft offered executable work") }
        confirmation.presentPreview()
        confirmation.requestSimulation()
        guard confirmation.showRunConfirmation, confirmation.confirmationCount == 2 else { fail("Selected chains missing from run confirmation") }
        confirmation.cancelRunConfirmation(); confirmation.simulateRun()
        guard confirmation.previewPhase == .review else { fail("Cancel confirmation started a run") }
        confirmation.requestSimulation()
        confirmation.experience.selected.removeAll()
        confirmation.simulateRun()
        guard confirmation.previewPhase == .review else { fail("Changed selection reused stale run confirmation") }
        await confirmation.shutdown()
        let partial = AppModel()
        partial.exploreDemo(); partial.presentPreview()
        partial.runScenario = .partialFailure
        partial.requestSimulation(); partial.simulateRun()
        await settle(partial)
        guard partial.previewPhase == .partial, partial.completedCount == 1, partial.partialCount == 1,
              partial.processedCount == 2, partial.activities.filter({ $0.outcome == .partial }).count == 1 else {
            fail("Partial sample failure was shown as a successful run or lost retained-step evidence")
        }
        partial.undoCandidate = partial.activities.first { $0.outcome == .partial }
        partial.simulateUndo()
        guard partial.activities.count == 2, let partialItem = partial.undoCandidate, partial.undoBlockReason(partialItem.id) != nil else { fail("Partial sample result offered an unchecked inverse") }
        await partial.shutdown()
        let failed = AppModel()
        failed.exploreDemo(); failed.presentPreview(); failed.runScenario = .failure
        failed.requestSimulation(); failed.simulateRun(); await settle(failed)
        guard failed.previewPhase == .failed, failed.failedCount == 2, failed.completedCount == 0,
              failed.activities.allSatisfy({ $0.outcome == .failed && $0.beforePath == $0.afterPath }) else { fail("Sample preflight denial fabricated completed effects") }
        await failed.shutdown()
        let paused = AppModel()
        paused.exploreDemo(); paused.presentPreview()
        paused.requestSimulation(); paused.simulateRun()
        paused.runScenario = .failure // Changing the provider must not alter the confirmed run.
        paused.pauseSimulation()
        await settle(paused)
        guard paused.previewPhase == .paused, paused.processedCount == 1, paused.completedCount == 1 else {
            fail("Pause did not finish one current sample boundary and stop the next file")
        }
        paused.resumeSimulation(); await settle(paused)
        guard paused.previewPhase == .finished, paused.processedCount == 2, paused.completedCount == 2 else { fail("Resuming sample work duplicated or changed confirmed chains") }
        let original = paused.activities[0]
        paused.undoCandidate = original
        paused.simulateUndo()
        guard paused.activities.count == 3, paused.activities.first?.outcome == .undone,
              paused.activities.first?.originalActivityID == original.id,
              paused.activities.first(where: { $0.id == original.id })?.undone == true else { fail("Sample inverse lost the original record or failed to append undo evidence") }
        paused.undoCandidate = original // A stale open sheet must not undo twice.
        paused.simulateUndo()
        guard paused.activities.count == 3, paused.undoBlockReason(original.id) != nil else { fail("Sample inverse could run twice") }
        paused.presentPreview(); paused.requestSimulation(); paused.simulateRun()
        paused.cancelSimulation(); paused.presentPreview(source: .draft)
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard paused.previewPhase == .review, paused.activities.count == 3 else { fail("Canceled sample completion overwrote a later preview") }
        await paused.shutdown()
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
        print("Native presentation smoke passed: confirmed preview, draft isolation, partial outcomes, pause, undo, cancellation, draft navigation and Quit")
    }
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
    @MainActor static func settle(_ model: AppModel) async {
        let deadline = Date().addingTimeInterval(6)
        while model.previewPhase == .running || model.previewPhase == .pausing {
            guard Date() < deadline else { fail("Sample run did not settle within its bounded fixture time") }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

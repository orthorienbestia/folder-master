import SwiftUI

enum WorkspaceDestination: Hashable { case folder(UUID), history }
enum PreviewPhase {
    case review, running, pausing, paused, finished, partial, failed, canceled
    var isActive: Bool { self == .running || self == .pausing || self == .paused }
}
enum DemoPreviewSource { case savedRule, draft }
enum DemoRunScenario: String, CaseIterable, Identifiable {
    case success = "Successful run", partialFailure = "Partial move failure", failure = "Permission failure"
    var id: String { rawValue }
}
enum DemoActivityOutcome: String { case completed = "Completed", partial = "Partial", failed = "Failed", undone = "Undo simulation" }
enum QuitDecision { case save, discard, cancel }

struct DemoActivity: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let time = Date()
    var outcome: DemoActivityOutcome = .completed
    var undone = false
    var originalActivityID: UUID?
    var beforePath = ""
    var afterPath = ""
    var steps: [String] {
        switch outcome {
        case .completed: return ["Rename completed", "Finance tag added", "Move completed"]
        case .partial: return ["Rename completed", "Finance tag added", "Move failed: destination unavailable"]
        case .failed: return ["Preflight failed: destination permission denied", "No actions started"]
        case .undone: return ["Move back simulated", "Previous tag values restored in sample state", "Original name restored in sample state"]
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: WorkspaceDestination?
    @Published var demo = false
    @Published var folders: [DemoFolder] = []
    @Published var experience = ExperienceState()
    @Published var selectedRuleID: UUID?
    @Published var draft: DemoRule?
    @Published var showUnsaved = false
    @Published var showPreview = false
    @Published var showRunConfirmation = false
    @Published private(set) var previewSource: DemoPreviewSource = .savedRule
    @Published private(set) var previewRuleName = ""
    @Published var previewPhase: PreviewPhase = .review
    @Published var completedCount = 0
    @Published var processedCount = 0
    @Published var partialCount = 0
    @Published var failedCount = 0
    @Published var runScenario: DemoRunScenario = .success
    @Published private(set) var runTotal = 0
    @Published var activities: [DemoActivity] = []
    @Published var undoCandidate: DemoActivity?
    @Published var engineStatus = "Connecting local engine…"
    @Published var enginePaused = true
    @Published var enginePending = false
    @Published var error: String?
    @Published var savedFeedback = false
    @Published var storedFolders: [StoredFolder] = []
    @Published var workspaceReady = false
    @Published var workspaceConnecting = false
    @Published var folderPending = false
    @Published var selectedLiveFolderID: String?
    @Published var liveDraft: StoredFolder?
    @Published var showAddFolder = false
    @Published var folderCandidate: FolderCandidate?
    @Published var showLiveUnsaved = false
    @Published var folderSavedFeedback = false
    @Published var quitPending = false
    private enum PendingLiveAction { case select(String?), demo }
    private var pendingLiveAction: PendingLiveAction?
    private enum PendingEditorAction { case select(UUID?), create }
    private var pendingEditorAction: PendingEditorAction?
    private var started = false
    private var simulation: Task<Void, Never>?
    private var approvedRows: [DemoPreviewRow]?
    private var approvedScenario = DemoRunScenario.success
    private var activeRows: [DemoPreviewRow] = []
    private var activeScenario = DemoRunScenario.success
    private var simulationID = UUID()
    private let dataDirectory: URL?
    let engine = EngineClient()

    init(dataDirectory: URL? = nil) {
        #if DEBUG
        self.dataDirectory = dataDirectory ?? ProcessInfo.processInfo.environment["FOLDER_MASTER_TEST_DATA_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        #else
        self.dataDirectory = dataDirectory
        #endif
    }

    var dirty: Bool { draft != experience.rules.first { $0.id == selectedRuleID } }
    var validDraft: Bool {
        guard let draft else { return false }
        return !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.conditions.isEmpty && !draft.actions.isEmpty
    }
    var liveDirty: Bool { liveDraft != storedFolders.first { $0.id == selectedLiveFolderID } }
    var validLiveDraft: Bool {
        guard let liveDraft else { return false }
        return !liveDraft.display_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && liveDraft.display_name.count <= 200
    }

    func connect() async {
        guard !started, !workspaceConnecting else { return }
        started = true
        workspaceConnecting = true
        defer { workspaceConnecting = false }
        do {
            let current = try await engine.request(op: "status")
            let reply: EngineReply
            if current.payload.store_open == true { reply = current }
            else {
                let directory: URL
                if let dataDirectory { directory = dataDirectory }
                else {
                    let parent = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    directory = parent.appendingPathComponent("Folder Master", isDirectory: true)
                }
                reply = try await engine.openStore(at: directory)
            }
            guard reply.payload.store_open == true else { throw EngineClientError.protocolMismatch }
            enginePaused = reply.payload.paused ?? true
            storedFolders = try await engine.listFolders()
            workspaceReady = true
            engineStatus = "Local workspace connected · Rust \(reply.payload.engine_version ?? "")"
            if selectedLiveFolderID == nil { loadLiveFolder(storedFolders.first?.id) }
        } catch { self.error = error.localizedDescription; engineStatus = "Local storage unavailable"; workspaceReady = false }
    }

    func retryStorage() async {
        guard !workspaceReady, !workspaceConnecting else { return }
        error = nil; started = false
        await connect()
    }

    func setPaused(_ paused: Bool) {
        guard !enginePending, workspaceReady, !quitPending else { return }
        enginePending = true
        Task {
            defer { enginePending = false }
            do {
                let reply = try await engine.request(op: "set_paused", paused: paused)
                guard reply.type == "completed", let actual = reply.payload.paused else { throw EngineClientError.protocolMismatch }
                enginePaused = actual
            } catch { self.error = error.localizedDescription }
        }
    }

    func exploreDemo() {
        guard !folderPending, !quitPending else { return }
        if liveDirty { pendingLiveAction = .demo; showLiveUnsaved = true; return }
        enterDemo()
    }
    private func enterDemo() {
        guard !demo else { return }
        demo = true
        folders = DemoSamples.folders
        experience.rules = DemoSamples.rules
        destination = .folder(folders[0].id)
        selectRule(experience.rules[0].id)
    }

    func selectLiveFolder(_ id: String?) {
        guard !folderPending, !quitPending else { return }
        guard selectedLiveFolderID != id else { return }
        if liveDirty { pendingLiveAction = .select(id); showLiveUnsaved = true; return }
        loadLiveFolder(id)
    }
    private func loadLiveFolder(_ id: String?) {
        selectedLiveFolderID = id
        liveDraft = storedFolders.first { $0.id == id }
        folderSavedFeedback = false
    }
    func discardLiveDraft() { guard !folderPending, !quitPending else { return }; loadLiveFolder(selectedLiveFolderID) }
    func resolveLiveUnsaved(save: Bool) async {
        guard !folderPending, !quitPending else { return }
        if save, !(await saveLiveFolder()) { return }
        let action = pendingLiveAction; pendingLiveAction = nil
        discardLiveDraft()
        switch action {
        case .select(let id): loadLiveFolder(id)
        case .demo: enterDemo()
        case nil: break
        }
    }
    func saveLiveFolder() async -> Bool {
        guard !quitPending else { return false }
        return await persistLiveFolderDraft()
    }
    private func persistLiveFolderDraft() async -> Bool {
        guard let draft = liveDraft, validLiveDraft, workspaceReady, !folderPending else { return false }
        folderPending = true; error = nil
        defer { folderPending = false }
        do {
            let saved = try await engine.updateFolder(draft)
            if let index = storedFolders.firstIndex(where: { $0.id == saved.id }) { storedFolders[index] = saved }
            liveDraft = saved; folderSavedFeedback = true
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func chooseFolder() {
        guard workspaceReady, !folderPending, !quitPending else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.resolvesAliases = false
        panel.prompt = "Choose Folder"
        panel.message = "Choose a local folder to configure. This build will not scan or organize its files."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let candidate = try await Task.detached(priority: .userInitiated) { try NativeFolderAccess.candidate(for: url) }.value
                    guard self?.quitPending == false else { return }
                    self?.folderCandidate = candidate; self?.error = nil; self?.showAddFolder = true
                } catch { self?.error = error.localizedDescription }
            }
        }
    }
    func addLiveFolder(name: String) async -> Bool {
        guard let candidate = folderCandidate, workspaceReady, !folderPending, !quitPending else { return false }
        folderPending = true; error = nil
        defer { folderPending = false }
        do {
            let saved = try await engine.addFolder(candidate, name: name)
            storedFolders.append(saved)
            // Preserve any unsaved edits in the current folder; selecting the
            // new folder goes through the same navigation guard as the sidebar.
            if liveDirty { pendingLiveAction = .select(saved.id); showLiveUnsaved = true }
            else { loadLiveFolder(saved.id) }
            showAddFolder = false; folderCandidate = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeLiveFolder(_ folder: StoredFolder) async {
        guard workspaceReady, !folderPending, !quitPending else { return }
        folderPending = true; error = nil
        defer { folderPending = false }
        do {
            try await engine.removeFolder(folder)
            storedFolders.removeAll { $0.id == folder.id }
            loadLiveFolder(storedFolders.first?.id)
        } catch { self.error = error.localizedDescription }
    }

    func selectRule(_ id: UUID?) {
        guard selectedRuleID != id else { return }
        if dirty && selectedRuleID != id { pendingEditorAction = .select(id); showUnsaved = true; return }
        loadRule(id)
    }

    private func loadRule(_ id: UUID?) {
        selectedRuleID = id
        draft = experience.rules.first { $0.id == id }
        savedFeedback = false
    }

    func resolveUnsaved(save: Bool) {
        if save { saveDraft() }
        let action = pendingEditorAction
        pendingEditorAction = nil
        showUnsaved = false
        switch action {
        case .select(let id): loadRule(id)
        case .create: createRule()
        case nil: break
        }
    }

    func saveDraft() {
        guard validDraft, let draft, let index = experience.rules.firstIndex(where: { $0.id == draft.id }) else { return }
        experience.rules[index] = draft
        savedFeedback = true
    }

    func discardDraft() { loadRule(selectedRuleID) }

    func addRule() {
        guard !dirty else { pendingEditorAction = .create; showUnsaved = true; return }
        createRule()
    }

    private func createRule() {
        let rule = DemoRule(name: "Untitled Rule", conditions: ["Name contains "], actions: [])
        experience.rules.append(rule)
        loadRule(rule.id)
    }

    func duplicateSelected() {
        guard let id = selectedRuleID, !dirty else { return }
        experience.duplicateRule(id)
    }

    var confirmationCount: Int { approvedRows?.count ?? 0 }
    func presentPreview(source: DemoPreviewSource = .savedRule) {
        guard !previewPhase.isActive else { return }
        simulation?.cancel(); simulationID = UUID()
        approvedRows = nil; showRunConfirmation = false
        previewSource = source
        previewRuleName = source == .draft ? draft?.name ?? "Untitled draft" : experience.rules.first { $0.id == selectedRuleID }?.name ?? "Saved rules"
        experience.rows = DemoSamples.preview
        experience.selectReady()
        previewPhase = .review
        completedCount = 0
        processedCount = 0; partialCount = 0; failedCount = 0; runTotal = 0
        showPreview = true
    }

    func requestSimulation() {
        guard demo, previewSource == .savedRule, previewPhase == .review, !experience.executableSelection.isEmpty else { return }
        approvedRows = experience.executableSelection
        approvedScenario = runScenario
        showRunConfirmation = true
    }
    func cancelRunConfirmation() { approvedRows = nil; showRunConfirmation = false }
    func simulateRun() {
        guard previewSource == .savedRule, previewPhase == .review, let rows = approvedRows,
              !rows.isEmpty, rows == experience.executableSelection else { cancelRunConfirmation(); return }
        activeRows = rows; activeScenario = approvedScenario; runTotal = rows.count
        cancelRunConfirmation()
        continueSimulation()
    }

    private func continueSimulation() {
        let token = UUID(); simulationID = token
        previewPhase = .running
        simulation = Task {
            for (index, row) in activeRows.enumerated().dropFirst(processedCount) {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                catch { if simulationID == token { previewPhase = .canceled }; return }
                guard !Task.isCancelled, simulationID == token else { return }
                let outcome: DemoActivityOutcome
                let detail: String
                if activeScenario == .failure {
                    outcome = .failed; failedCount += 1
                    detail = "Sample permission denial before the first step. No effects retained."
                } else if activeScenario == .partialFailure && index == activeRows.count - 1 {
                    outcome = .partial; partialCount += 1
                    detail = "Sample rename and tag retained; move failed. Inspect before retrying."
                } else {
                    outcome = .completed; completedCount += 1
                    detail = "Sample rename → tag → move completed. No real files changed."
                }
                let before = "/Sample/Downloads/\(row.name)"
                let after = outcome == .failed ? before : outcome == .partial ? "/Sample/Downloads/2026-11-11-\(row.name)" : "/Sample/\(row.destination)2026-11-11-\(row.name)"
                activities.insert(DemoActivity(name: row.name, detail: detail, outcome: outcome, beforePath: before, afterPath: after), at: 0)
                processedCount += 1
                if previewPhase == .pausing && processedCount < activeRows.count { previewPhase = .paused; return }
            }
            previewPhase = partialCount > 0 || (failedCount > 0 && completedCount > 0) ? .partial : failedCount > 0 ? .failed : .finished
        }
    }

    func cancelSimulation() {
        guard previewPhase.isActive else { return }
        simulation?.cancel(); simulationID = UUID(); previewPhase = .canceled
    }
    func pauseSimulation() { if previewPhase == .running { previewPhase = .pausing } }
    func resumeSimulation() { if previewPhase == .paused { continueSimulation() } }
    func undoBlockReason(_ id: UUID) -> String? {
        guard let item = activities.first(where: { $0.id == id }) else { return "This sample record is no longer available." }
        if previewPhase.isActive { return "Finish or cancel the sample run before previewing its inverse." }
        if item.undone { return "This sample result already has an undo record. Redo is not supported." }
        switch item.outcome {
        case .completed: return nil
        case .partial: return "The move failed after rename and tag steps. A real inverse must inspect the retained steps before it can be offered."
        case .failed: return "No actions started, so there is nothing to undo."
        case .undone: return "This is an undo record. Redo is not supported."
        }
    }
    func simulateUndo() {
        guard let candidate = undoCandidate, undoBlockReason(candidate.id) == nil,
              let index = activities.firstIndex(where: { $0.id == candidate.id }) else { return }
        let original = activities[index]
        activities[index].undone = true
        activities.insert(DemoActivity(name: original.name, detail: "Sample inverse appended; original evidence retained. No real files changed.", outcome: .undone, originalActivityID: original.id, beforePath: original.afterPath, afterPath: original.beforePath), at: 0)
        undoCandidate = nil
    }
    func prepareForQuit(confirm: @MainActor () async -> QuitDecision) async -> Bool {
        guard !quitPending else { return false }
        quitPending = true
        // Allow acknowledged configuration updates to settle before inspecting
        // dirty state or shutting down the worker. This never waits on the UI
        // thread synchronously. File-effect draining remains a later milestone.
        do {
            while folderPending || enginePending || workspaceConnecting { try await Task.sleep(nanoseconds: 10_000_000) }
        } catch { quitPending = false; return false }
        if liveDirty {
            switch await confirm() {
            case .cancel: quitPending = false; return false
            case .save:
                guard await persistLiveFolderDraft() else { quitPending = false; return false }
            case .discard: break
            }
        }
        return true
    }
    func shutdown() async { simulation?.cancel(); await engine.shutdown() }
}

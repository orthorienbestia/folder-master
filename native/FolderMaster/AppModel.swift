import SwiftUI
import Combine

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
    @Published private(set) var draftSessionID = UUID()
    @Published var showUnsaved = false
    @Published var showPreview = false
    @Published var showRunConfirmation = false
    @Published private(set) var previewSource: DemoPreviewSource = .savedRule
    @Published private(set) var previewRuleName = ""
    @Published private(set) var previewFolderName = ""
    @Published private(set) var previewFolderEnabled = false
    @Published var previewPhase: PreviewPhase = .review
    @Published var completedCount = 0
    @Published var processedCount = 0
    @Published var partialCount = 0
    @Published var failedCount = 0
    @Published var runScenario: DemoRunScenario = .success
    @Published private(set) var runTotal = 0
    @Published var activities: [DemoActivity] = []
    @Published var undoCandidate: DemoActivity?
    @Published private(set) var demoReconnectID: UUID?
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
    private enum PendingEditorAction { case select(UUID?), create, destination(WorkspaceDestination?), leave }
    private var pendingEditorAction: PendingEditorAction?
    private var started = false
    private var simulation: Task<Void, Never>?
    private var approvedRows: [DemoPreviewRow]?
    private var approvedScenario = DemoRunScenario.success
    private var activeRows: [DemoPreviewRow] = []
    private var activeScenario = DemoRunScenario.success
    private var simulationID = UUID()
    private var demoInitialized = false
    private var activeDemoFolderID: UUID?
    private var demoRuleSets: [UUID: [DemoRule]] = [:]
    private var demoRuleSelections: [UUID: UUID] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var reconnectToken = UUID()
    private var previewFolderID: UUID?
    private var historyAfterPreview = false
    private var newDemoRuleID: UUID?
    private var previousDemoRuleID: UUID?
    private let dataDirectory: URL?
    let engine: EngineClient
    let liveRules: LiveRuleModel
    private var ruleChanges: AnyCancellable?

    init(dataDirectory: URL? = nil) {
        let client = EngineClient(); engine = client; liveRules = LiveRuleModel(engine: client)
        #if DEBUG
        self.dataDirectory = dataDirectory ?? ProcessInfo.processInfo.environment["FOLDER_MASTER_TEST_DATA_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        #else
        self.dataDirectory = dataDirectory
        #endif
        ruleChanges = liveRules.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var dirty: Bool {
        (newDemoRuleID != nil && selectedRuleID == newDemoRuleID) || draft != experience.rules.first { $0.id == selectedRuleID }
    }
    var validDraft: Bool {
        guard let draft else { return false }
        return !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.name.count <= 200 && draft.conditions.validationIssues.isEmpty && draft.actions.issues(enabled: draft.enabled, conditions: draft.conditions).isEmpty
    }
    var draftIsNew: Bool { newDemoRuleID != nil && draft?.id == newDemoRuleID }
    var liveDirty: Bool { liveDraft != storedFolders.first { $0.id == selectedLiveFolderID } }
    var workspaceDirty: Bool { liveDirty || liveRules.dirty }
    var validWorkspaceDrafts: Bool { (!liveDirty || validLiveDraft) && (!liveRules.dirty || liveRules.valid) }
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
        guard !folderPending, !liveRules.pending, !quitPending else { return }
        if workspaceDirty { pendingLiveAction = .demo; showLiveUnsaved = true; return }
        enterDemo()
    }
    private func enterDemo() {
        guard !demo else { return }
        demo = true
        if !demoInitialized {
            folders = DemoSamples.folders
            demoRuleSets[folders[0].id] = DemoSamples.rules
            demoRuleSets[folders[1].id] = [DemoSamples.scanRule]
            demoRuleSets[folders[2].id] = []
            demoInitialized = true
            loadDemoDestination(.folder(folders[0].id))
        }
    }

    func selectLiveFolder(_ id: String?) {
        guard !folderPending, !liveRules.pending, !quitPending else { return }
        guard selectedLiveFolderID != id else { return }
        if workspaceDirty { pendingLiveAction = .select(id); showLiveUnsaved = true; return }
        loadLiveFolder(id)
    }
    private func loadLiveFolder(_ id: String?) {
        selectedLiveFolderID = id
        liveDraft = storedFolders.first { $0.id == id }
        folderSavedFeedback = false
        liveRules.openFolder(id)
    }
    func discardLiveDraft() { guard !folderPending, !quitPending else { return }; liveDraft = storedFolders.first { $0.id == selectedLiveFolderID }; folderSavedFeedback = false }
    func resolveLiveUnsaved(save: Bool) async {
        guard !folderPending, !liveRules.pending, !quitPending else { return }
        if save {
            if liveRules.dirty, !(await liveRules.save()) { error = liveRules.error; return }
            if liveDirty, !(await saveLiveFolder()) { return }
        }
        let action = pendingLiveAction; pendingLiveAction = nil
        discardLiveDraft()
        if liveRules.dirty { liveRules.discard() }
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
            if workspaceDirty { pendingLiveAction = .select(saved.id); showLiveUnsaved = true }
            else { loadLiveFolder(saved.id) }
            showAddFolder = false; folderCandidate = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeLiveFolder(_ folder: StoredFolder) async {
        guard workspaceReady, !folderPending, !liveRules.pending, !quitPending else { return }
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
    var selectedDemoFolder: DemoFolder? {
        guard case .folder(let id) = destination else { return nil }
        return folders.first { $0.id == id }
    }
    var canPreviewDemo: Bool {
        demo && !quitPending && !previewPhase.isActive && selectedDemoFolder?.availability == .available && demoReconnectID != selectedDemoFolder?.id
    }
    func selectDemoDestination(_ destination: WorkspaceDestination?) {
        guard demo, !quitPending, !previewPhase.isActive, self.destination != destination else { return }
        if dirty { pendingEditorAction = .destination(destination); showUnsaved = true; return }
        storeDemoRules()
        loadDemoDestination(destination)
    }
    private func storeDemoRules() {
        guard let id = activeDemoFolderID else { return }
        demoRuleSets[id] = experience.rules
        demoRuleSelections[id] = selectedRuleID
    }
    private func loadDemoDestination(_ destination: WorkspaceDestination?) {
        if case .folder(let id) = destination {
            guard folders.contains(where: { $0.id == id }) else { return }
            activeDemoFolderID = id
            experience.rules = demoRuleSets[id] ?? []
            let previous = experience.rules.first { $0.id == demoRuleSelections[id] }
            loadRule(previous?.id ?? experience.rules.first?.id)
        }
        self.destination = destination
    }
    func leaveDemo() {
        guard demo, !quitPending, !previewPhase.isActive else { return }
        if dirty { pendingEditorAction = .leave; showUnsaved = true; return }
        storeDemoRules()
        reconnectTask?.cancel(); reconnectToken = UUID(); demoReconnectID = nil
        demo = false
    }
    func keepEditingDemo() { pendingEditorAction = nil; showUnsaved = false }
    func setDemoFolderEnabled(_ enabled: Bool) {
        guard demo, !quitPending, let folder = selectedDemoFolder, folder.availability == .available,
              let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].enabled = enabled
        folders[index].detail = enabled ? "Available · sample On" : "Available · sample Off"
    }
    func reconnectDemoFolder() {
        guard demo, !quitPending, demoReconnectID == nil, let folder = selectedDemoFolder,
              folder.availability == .unavailable else { return }
        let token = UUID(); reconnectToken = token; demoReconnectID = folder.id
        reconnectTask = Task {
            defer { if reconnectToken == token { demoReconnectID = nil } }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            guard !Task.isCancelled, reconnectToken == token, demo,
                  let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
            folders[index].availability = .available
            folders[index].detail = folders[index].enabled ? "Available · sample On" : "Available · sample Off"
        }
    }

    private func loadRule(_ id: UUID?) {
        draftSessionID = UUID()
        selectedRuleID = id
        draft = experience.rules.first { $0.id == id }
        savedFeedback = false
    }

    func resolveUnsaved(save: Bool) {
        if save, !saveDraft() { return }
        if !save { discardDraft() }
        let action = pendingEditorAction
        pendingEditorAction = nil
        showUnsaved = false
        switch action {
        case .select(let id): loadRule(id)
        case .create: createRule()
        case .destination(let target): selectDemoDestination(target)
        case .leave: leaveDemo()
        case nil: break
        }
    }

    func updateActionDraft(_ actions: ActionChainDraft, ruleID: UUID, sessionID: UUID) {
        guard draft?.id == ruleID, draftSessionID == sessionID, !quitPending else { return }
        draft?.actions = actions; savedFeedback = false
    }

    @discardableResult func saveDraft() -> Bool {
        guard validDraft, let draft, let index = experience.rules.firstIndex(where: { $0.id == draft.id }) else { return false }
        experience.rules[index] = draft
        draftSessionID = UUID()
        newDemoRuleID = nil; previousDemoRuleID = nil
        savedFeedback = true
        return true
    }

    func discardDraft() {
        if let id = newDemoRuleID, selectedRuleID == id {
            experience.rules.removeAll { $0.id == id }
            let previous = experience.rules.first { $0.id == previousDemoRuleID }
            newDemoRuleID = nil; previousDemoRuleID = nil
            loadRule(previous?.id ?? experience.rules.first?.id)
        } else { loadRule(selectedRuleID) }
    }

    func addRule() {
        guard demo, !quitPending, !previewPhase.isActive, selectedDemoFolder?.availability == .available else { return }
        guard !dirty else { pendingEditorAction = .create; showUnsaved = true; return }
        createRule()
    }

    private func createRule() {
        let rule = DemoRule(name: "Untitled Rule", conditions: .group(children: [.predicate()]), actions: .init())
        previousDemoRuleID = selectedRuleID; newDemoRuleID = rule.id
        experience.rules.append(rule)
        loadRule(rule.id)
    }

    func duplicateSelected() {
        guard let id = selectedRuleID, !dirty else { return }
        experience.duplicateRule(id)
    }

    var confirmationCount: Int { approvedRows?.count ?? 0 }
    func presentPreview(source: DemoPreviewSource = .savedRule) {
        guard canPreviewDemo, let folder = selectedDemoFolder, source != .draft || validDraft else { return }
        simulation?.cancel(); simulationID = UUID()
        approvedRows = nil; showRunConfirmation = false
        previewSource = source
        previewFolderID = folder.id; previewFolderName = folder.name; previewFolderEnabled = folder.enabled
        historyAfterPreview = false
        previewRuleName = source == .draft ? draft?.name ?? "Untitled draft" : experience.rules.first { $0.id == selectedRuleID && $0.id != newDemoRuleID }?.name ?? "Saved rules"
        experience.rows = source == .draft || experience.rules.contains(where: \.enabled) ? DemoSamples.preview(in: folder) : []
        experience.selectReady()
        previewPhase = .review
        completedCount = 0
        processedCount = 0; partialCount = 0; failedCount = 0; runTotal = 0
        showPreview = true
    }
    func requestHistoryAfterPreview() {
        guard showPreview, !previewPhase.isActive else { return }
        historyAfterPreview = true; showPreview = false
    }
    func previewDidDismiss() {
        cancelRunConfirmation()
        if historyAfterPreview { historyAfterPreview = false; selectDemoDestination(.history) }
    }

    func requestSimulation() {
        guard canPreviewDemo, previewFolderID == selectedDemoFolder?.id, previewSource == .savedRule, previewPhase == .review, !experience.executableSelection.isEmpty else { return }
        approvedRows = experience.executableSelection
        approvedScenario = runScenario
        showRunConfirmation = true
    }
    func cancelRunConfirmation() { approvedRows = nil; showRunConfirmation = false }
    func simulateRun() {
        guard canPreviewDemo, previewFolderID == selectedDemoFolder?.id, previewSource == .savedRule, previewPhase == .review, let rows = approvedRows,
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
                let before = row.sourcePath
                let after = outcome == .failed ? before : outcome == .partial ? row.renamedSourcePath : row.destinationPath
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
        liveRules.locked = true
        // Allow acknowledged configuration updates to settle before inspecting
        // dirty state or shutting down the worker. This never waits on the UI
        // thread synchronously. File-effect draining remains a later milestone.
        do {
            while folderPending || liveRules.pending || enginePending || workspaceConnecting { try await Task.sleep(nanoseconds: 10_000_000) }
        } catch { quitPending = false; liveRules.locked = false; return false }
        if workspaceDirty {
            switch await confirm() {
            case .cancel: quitPending = false; liveRules.locked = false; return false
            case .save:
                if liveRules.dirty, !(await liveRules.save(whileQuitting: true)) { error = liveRules.error; quitPending = false; liveRules.locked = false; return false }
                if liveDirty, !(await persistLiveFolderDraft()) { quitPending = false; liveRules.locked = false; return false }
            case .discard: break
            }
        }
        return true
    }
    func shutdown() async { simulation?.cancel(); reconnectTask?.cancel(); reconnectToken = UUID(); demoReconnectID = nil; await engine.shutdown() }
}

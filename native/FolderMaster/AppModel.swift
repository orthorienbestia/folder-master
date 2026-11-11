import SwiftUI

enum WorkspaceDestination: Hashable { case folder(UUID), history }
enum PreviewPhase { case review, running, finished, canceled }

struct DemoActivity: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let time = Date()
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
    @Published var previewPhase: PreviewPhase = .review
    @Published var completedCount = 0
    @Published var activities: [DemoActivity] = []
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
    private enum PendingLiveAction { case select(String?), demo }
    private var pendingLiveAction: PendingLiveAction?
    private enum PendingEditorAction { case select(UUID?), create }
    private var pendingEditorAction: PendingEditorAction?
    private var started = false
    private var simulation: Task<Void, Never>?
    let engine = EngineClient()

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
                let parent = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                reply = try await engine.openStore(at: parent.appendingPathComponent("Folder Master", isDirectory: true))
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
        guard !enginePending, workspaceReady else { return }
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
        guard !folderPending else { return }
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
        guard !folderPending else { return }
        guard selectedLiveFolderID != id else { return }
        if liveDirty { pendingLiveAction = .select(id); showLiveUnsaved = true; return }
        loadLiveFolder(id)
    }
    private func loadLiveFolder(_ id: String?) {
        selectedLiveFolderID = id
        liveDraft = storedFolders.first { $0.id == id }
        folderSavedFeedback = false
    }
    func discardLiveDraft() { loadLiveFolder(selectedLiveFolderID) }
    func resolveLiveUnsaved(save: Bool) async {
        guard !folderPending else { return }
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
        guard workspaceReady, !folderPending else { return }
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
                    self?.folderCandidate = candidate; self?.error = nil; self?.showAddFolder = true
                } catch { self?.error = error.localizedDescription }
            }
        }
    }
    func addLiveFolder(name: String) async -> Bool {
        guard let candidate = folderCandidate, workspaceReady, !folderPending else { return false }
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
        guard workspaceReady, !folderPending else { return }
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

    func presentPreview() {
        experience.rows = DemoSamples.preview
        experience.selectReady()
        previewPhase = .review
        completedCount = 0
        showPreview = true
    }

    func simulateRun() {
        guard previewPhase == .review, !experience.executableSelection.isEmpty else { return }
        let rows = experience.executableSelection
        previewPhase = .running
        simulation = Task {
            for row in rows {
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { previewPhase = .canceled; return }
                guard !Task.isCancelled else { previewPhase = .canceled; return }
                completedCount += 1
                activities.insert(DemoActivity(name: row.name, detail: "Simulated rename → tag → move. No file was read or changed."), at: 0)
            }
            previewPhase = .finished
        }
    }

    func cancelSimulation() { simulation?.cancel(); previewPhase = .canceled }
    func shutdown() async { simulation?.cancel(); await engine.shutdown() }
}

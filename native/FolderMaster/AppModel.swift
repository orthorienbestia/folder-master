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

    func connect() async {
        guard !started else { return }
        started = true
        do {
            let reply = try await engine.request(op: "status")
            guard reply.type == "completed" else { throw EngineClientError.protocolMismatch }
            enginePaused = reply.payload.paused ?? true
            engineStatus = "Rust \(reply.payload.engine_version ?? "") connected"
        } catch { self.error = error.localizedDescription; engineStatus = "Engine unavailable" }
    }

    func setPaused(_ paused: Bool) {
        guard !enginePending else { return }
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
        guard !demo else { return }
        demo = true
        folders = DemoSamples.folders
        experience.rules = DemoSamples.rules
        destination = .folder(folders[0].id)
        selectRule(experience.rules[0].id)
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

import SwiftUI

/// Saved configuration only. No matching, preview or file-effect state lives here.
@MainActor
final class LiveRuleModel: ObservableObject {
    @Published private(set) var folderID: String?
    @Published private(set) var summaries: [StoredRuleSummary] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var draft: DemoRule?
    @Published private(set) var revision: UInt64?
    @Published private(set) var pending = false
    @Published private(set) var loaded = false
    @Published var error: String?
    @Published private(set) var savedRevision: UInt64?
    @Published private(set) var sessionID = UUID()
    @Published var showUnsaved = false
    var locked = false
    private let engine: EngineClient
    private var baseline: DemoRule?
    private var generation = UUID()
    private var previousID: UUID?
    private enum Navigation {
        case select(UUID?)
        case create
    }
    private var navigation: Navigation?
    init(engine: EngineClient) { self.engine = engine }
    var dirty: Bool { draft != baseline }
    var isNew: Bool { draft != nil && revision == nil }
    var valid: Bool { draft.flatMap { try? StoredRuleDefinition(draft: $0) } != nil }

    @discardableResult func openFolder(_ id: String?) -> Task<Void, Never> {
        let token = UUID()
        generation = token
        sessionID = UUID()
        folderID = id
        summaries = []
        selectedID = nil
        draft = nil
        baseline = nil
        revision = nil
        savedRevision = nil
        error = nil
        loaded = false
        pending = id != nil
        return Task {
            defer { if generation == token { pending = false } }
            guard let id else {
                loaded = true
                return
            }
            do {
                let list = try await engine.listRules(folderID: id)
                guard generation == token else { return }
                summaries = list
                loaded = true
                if let first = list.first { try await loadRule(first.id, token: token) }
            } catch { if generation == token { self.error = error.localizedDescription } }
        }
    }
    private func loadRule(_ id: UUID?, token: UUID) async throws {
        guard generation == token else { return }
        guard let id else {
            selectedID = nil
            draft = nil
            baseline = nil
            revision = nil
            sessionID = UUID()
            return
        }
        guard let record = try await engine.rule(id: id), record.folder_id == folderID else {
            throw EngineClientError.protocolMismatch
        }
        var value = try record.definition.draft()
        // Selection-time executable evidence is not durable authorization.
        // Refresh only metadata off the main actor when loading a saved script.
        for index in value.actions.steps.indices where value.actions.steps[index].kind == .script {
            let script = value.actions.steps[index].script
            func checked(_ reference: ActionLocationDraft?) async -> ActionLocationDraft? {
                guard var reference else { return nil }
                let original = reference
                reference.wasExecutable = await Task.detached(priority: .userInitiated) {
                    guard let url = try? NativeFolderAccess.url(for: original.path) else { return false }
                    return (try? ActionLocationDraft.file(url, executable: true)) != nil
                }.value
                return reference
            }
            if script.interpreter == .executable { value.actions.steps[index].script.file = await checked(script.file) }
            if script.interpreter == .custom {
                value.actions.steps[index].script.customInterpreter = await checked(script.customInterpreter)
            }
        }
        guard generation == token else { return }
        selectedID = id
        revision = record.revision
        draft = value
        baseline = value
        savedRevision = nil
        sessionID = UUID()
    }
    func select(_ id: UUID?) {
        guard !pending, !locked, id != selectedID else { return }
        if dirty {
            navigation = .select(id)
            showUnsaved = true
            return
        }
        navigate(.select(id))
    }
    func create() {
        guard !pending, !locked, folderID != nil, loaded else { return }
        if dirty {
            navigation = .create
            showUnsaved = true
            return
        }
        navigate(.create)
    }
    private func navigate(_ action: Navigation) {
        switch action {
        case .create:
            previousID = selectedID
            let rule = DemoRule(name: "Untitled Rule", conditions: .group(children: [.predicate()]), actions: .init())
            draft = rule
            baseline = nil
            selectedID = rule.id
            revision = nil
            savedRevision = nil
            error = nil
            sessionID = UUID()
        case .select(let id):
            pending = true
            error = nil
            let token = generation
            Task {
                defer { if generation == token { pending = false } }
                do { try await loadRule(id, token: token) } catch {
                    if generation == token { self.error = error.localizedDescription }
                }
            }
        }
    }
    func resolveUnsaved(save: Bool) async {
        guard !pending, !locked else { return }
        if save, !(await self.save()) { return }
        let target = navigation
        navigation = nil
        showUnsaved = false
        if let target { navigate(target) }
    }
    func keepEditing() {
        navigation = nil
        showUnsaved = false
    }
    func reload() {
        guard !pending, !locked else { return }
        if dirty {
            navigation = .select(revision == nil ? previousID : selectedID)
            showUnsaved = true
        } else if let selectedID {
            navigate(.select(selectedID))
        } else {
            openFolder(folderID)
        }
    }
    func discard() {
        guard !pending, !locked else { return }
        if revision == nil {
            draft = nil
            baseline = nil
            selectedID = nil
            navigate(.select(previousID ?? summaries.first?.id))
        } else {
            draft = baseline
            sessionID = UUID()
            savedRevision = nil
            error = nil
        }
    }
    func update(_ value: DemoRule, session: UUID) {
        guard !pending, !locked, sessionID == session, draft?.id == value.id else { return }
        draft = value
        savedRevision = nil
    }
    @discardableResult func save(whileQuitting: Bool = false) async -> Bool {
        guard !pending, !locked || whileQuitting, let folderID, let draft else { return false }
        pending = true
        error = nil
        savedRevision = nil
        defer { pending = false }
        do {
            let definition = try StoredRuleDefinition(draft: draft)
            let issues = try await engine.validateRule(definition)
            if let first = issues.first {
                throw EngineClientError.operation(code: first.code, message: "\(first.path): \(first.message)")
            }
            let record = try await engine.saveRule(definition, folderID: folderID, expectedRevision: revision)
            guard record.folder_id == folderID, try record.definition.matches(definition) else {
                throw EngineClientError.protocolMismatch
            }
            // The acknowledged wire configuration is identical. Keep current
            // form-only state, focus identities and session acknowledgements;
            // these are never serialized as execution approval.
            let saved = draft
            self.draft = saved
            baseline = saved
            revision = record.revision
            savedRevision = record.revision
            sessionID = UUID()
            let summary = StoredRuleSummary(
                id: saved.id, revision: record.revision, name: saved.name, enabled: saved.enabled,
                condition_count: saved.conditions.predicateCount, action_count: saved.actions.count)
            if let index = summaries.firstIndex(where: { $0.id == saved.id }) {
                summaries[index] = summary
            } else {
                summaries.append(summary)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

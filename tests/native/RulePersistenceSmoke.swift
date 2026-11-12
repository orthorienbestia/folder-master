import Foundation

@main
struct RulePersistenceSmoke {
    @MainActor static func main() async {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "folder-master-rules-\(UUID().uuidString)", isDirectory: true)
        let engine = EngineClient()
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
            try fm.createDirectory(at: inbox, withIntermediateDirectories: false)
            let sentinel = inbox.appendingPathComponent("original.txt")
            try Data("untouched".utf8).write(to: sentinel)
            let scriptURL = root.appendingPathComponent("fixture.sh")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: scriptURL)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            let location = try ActionLocationDraft.folder(inbox)
            _ = try await engine.openStore(at: root.appendingPathComponent("data", isDirectory: true))
            let folder = try await engine.addFolder(NativeFolderAccess.candidate(for: inbox), name: "Inbox")
            var count = 0
            for field in ConditionField.allCases {
                for op in field.operators {
                    var p = ConditionPredicateDraft(field: field, operation: op, text: "invoice")
                    p.nameScope = .stem
                    p.caseSensitive = true
                    switch field {
                    case .extensionName: p.text = ".PDF, gz"
                    case .kind:
                        p.kind = .custom
                        p.text = "public.jpeg"
                    case .size:
                        p.sizeUnit = .gib
                        p.text = "0.5"
                        p.upperText = "1.75"
                    case .date:
                        p.text = "1.5"
                        p.startDate = Date(timeIntervalSince1970: 1_700_000_000)
                        p.endDate = p.startDate.addingTimeInterval(3600)
                    case .tags: p.tagNames = ["Annual, reports", "Work"]
                    case .label: p.labels = [.none, .blue]
                    case .text: p.textSource = .forceOCR
                    default: break
                    }
                    let rule = DemoRule(
                        name: "\(field.rawValue) \(op.rawValue)", conditions: .group(children: [.predicate(p)]),
                        actions: .init(steps: [ActionDraft(.rename)]))
                    let definition = try StoredRuleDefinition(draft: rule)
                    let issues = try await engine.validateRule(definition)
                    guard issues.isEmpty else {
                        throw Failure.check("Rust rejected native condition \(rule.name): \(issues[0].message)")
                    }
                    let record = try await engine.saveRule(definition, folderID: folder.id, expectedRevision: nil)
                    _ = try record.definition.draft()
                    count += 1
                }
            }
            for sizeUnit in ConditionSizeUnit.allCases {
                var p = ConditionPredicateDraft(field: .size)
                // Maximum integer bytes survives JSONSerialization and the
                // retained display-unit conversion without Double rounding.
                p.sizeUnit = .bytes
                p.text = String(UInt64.max)
                let rule = DemoRule(
                    name: "Maximum \(sizeUnit.rawValue)", conditions: .group(children: [.predicate(p)]),
                    actions: .init(steps: [ActionDraft(.rename)]))
                let json = String(decoding: try JSONEncoder().encode(StoredRuleDefinition(draft: rule)), as: UTF8.self)
                    .replacingOccurrences(
                        of: "\"unit\":\"bytes\"", with: "\"unit\":\"\(sizeUnit.rawValue.lowercased())\"")
                let definition = try JSONDecoder().decode(StoredRuleDefinition.self, from: Data(json.utf8))
                let record = try await engine.saveRule(definition, folderID: folder.id, expectedRevision: nil)
                let loaded = try record.definition.draft().conditions.children[0].predicateValue!
                guard loaded.sizeUnit == sizeUnit, loaded.sizeUnit.bytes(from: loaded.text) == UInt64.max else {
                    throw Failure.check("Maximum byte threshold rounded in bridge")
                }
                _ = try StoredRuleDefinition(draft: record.definition.draft())
                count += 1
            }
            for kind in ConditionKind.allCases {
                var p = ConditionPredicateDraft(field: .kind)
                p.kind = kind
                p.text = "public.jpeg"
                let rule = DemoRule(
                    name: "Kind \(kind.rawValue)",
                    conditions: .group(.any, children: [.group(.none, children: [.predicate(p)])]),
                    actions: .init(steps: [ActionDraft(.rename)]))
                _ = try await engine.saveRule(
                    StoredRuleDefinition(draft: rule), folderID: folder.id, expectedRevision: nil
                ).definition.draft()
                count += 1
            }
            var selected: StoredRuleRecord?
            for kind in ActionKind.allCases {
                var action = ActionDraft(kind)
                action.destination.root = location
                action.tagNames = ["Annual, reports"]
                action.tagsMode = .replace
                action.replaceTagsAcknowledged = true
                action.labelMode = .clear
                action.deleteAcknowledged = true
                action.script.file = try .file(scriptURL)
                action.script.interpreter = .custom
                action.script.customInterpreter = try .file(scriptURL, executable: true)
                action.script.arguments = [.init(value: ""), .init(value: "literal $HOME; $(never) a,b")]
                action.script.publishOutput = true
                action.script.destination.root = location
                action.acknowledgeScript(true)
                let rule = DemoRule(
                    name: kind.rawValue, conditions: .group(children: [.predicate(.init(text: "invoice"))]),
                    actions: .init(steps: [action]))
                let record = try await engine.saveRule(
                    StoredRuleDefinition(draft: rule), folderID: folder.id, expectedRevision: nil)
                let loaded = try record.definition.draft()
                guard loaded.actions.steps[0].kind == kind, loaded.id == rule.id else {
                    throw Failure.check("Native action roundtrip changed identity/kind")
                }
                if kind == .script {
                    guard !loaded.actions.steps[0].scriptAcknowledged,
                        loaded.actions.steps[0].script.arguments.map(\.value) == action.script.arguments.map(\.value)
                    else { throw Failure.check("Script argv or approval boundary changed") }
                }
                if kind == .rename { selected = record }
                count += 1
            }
            func fixture(
                _ predicate: ConditionPredicateDraft, _ action: ActionDraft, behavior: ActionRuleBehavior = .stop
            ) async throws {
                let rule = DemoRule(
                    name: "Option fixture \(count)", conditions: .group(children: [.predicate(predicate)]),
                    actions: .init(steps: [action], behavior: behavior))
                let record = try await engine.saveRule(
                    StoredRuleDefinition(draft: rule), folderID: folder.id, expectedRevision: nil)
                _ = try record.definition.draft()
                count += 1
            }
            for source in ConditionDateField.allCases {
                var p = ConditionPredicateDraft(field: .date, text: " 1.5 ")
                p.dateField = source
                try await fixture(p, ActionDraft(.rename))
            }
            for source in ContentSource.allCases {
                var p = ConditionPredicateDraft(field: .text, text: "invoice")
                p.textSource = source
                try await fixture(p, ActionDraft(.rename))
            }
            for mode in ActionTagMode.allCases {
                var a = ActionDraft(.metadata)
                a.tagsMode = mode
                a.tagNames = mode == .replace ? [] : ["Exact, tag"]
                a.replaceTagsAcknowledged = true
                a.labelMode = .set
                a.label = .purple
                try await fixture(.init(text: "invoice"), a)
            }
            for interpreter in ActionInterpreter.allCases {
                var a = ActionDraft(.script)
                a.script.file = try .file(scriptURL, executable: true)
                a.script.interpreter = interpreter
                a.script.customInterpreter = try .file(scriptURL, executable: true)
                a.script.timeout = " 30 "
                a.acknowledgeScript(true)
                try await fixture(.init(text: "invoice"), a)
            }
            for regex in [false, true] {
                var a = ActionDraft(.rename)
                a.renameMode = .replace
                a.find = "old"
                a.replacement = "new"
                a.regex = regex
                a.replaceAll = true
                a.preserveExtension = false
                try await fixture(.init(text: "invoice"), a, behavior: .continueRules)
            }
            guard try await engine.listRules(folderID: folder.id).count == count else {
                throw Failure.check("Paginated native summaries lost rules")
            }
            let original = selected!
            var edit = try original.definition.draft()
            edit.name = "Saved revision two"
            _ = try await engine.saveRule(StoredRuleDefinition(draft: edit), folderID: folder.id, expectedRevision: 1)
            do {
                _ = try await engine.saveRule(original.definition, folderID: folder.id, expectedRevision: 1)
                throw Failure.check("Stale revision replaced saved configuration")
            } catch EngineClientError.operation(let code, _) {
                guard code == "stale_revision" else { throw Failure.check(code) }
            }
            let model = LiveRuleModel(engine: engine)
            await model.openFolder(folder.id).value
            model.select(edit.id)
            await idle(model)
            guard model.revision == 2 else { throw Failure.check("Controller did not load current revision") }
            var draft = model.draft!
            draft.name = "Unsaved edit"
            let oldSession = model.sessionID
            model.update(draft, session: oldSession)
            model.create()
            guard model.showUnsaved, model.draft?.name == "Unsaved edit" else {
                throw Failure.check("New rule discarded a dirty draft")
            }
            model.keepEditing()
            model.discard()
            model.update(draft, session: oldSession)
            guard !model.dirty, model.draft?.name == "Saved revision two" else {
                throw Failure.check("Delayed edit bypassed discarded session")
            }
            draft = model.draft!
            draft.name = "Controller save"
            model.update(draft, session: model.sessionID)
            guard await model.save(), !model.dirty, model.revision == 3 else {
                throw Failure.check("Controller save did not acknowledge durable revision")
            }
            var external = model.draft!
            external.name = "Changed elsewhere"
            _ = try await engine.saveRule(
                StoredRuleDefinition(draft: external), folderID: folder.id, expectedRevision: 3)
            draft = model.draft!
            draft.name = "Keep my stale draft"
            model.update(draft, session: model.sessionID)
            guard !(await model.save()), model.dirty, model.draft?.name == "Keep my stale draft", model.revision == 3,
                model.error != nil
            else { throw Failure.check("Failed stale save discarded draft or invented success") }
            model.reload()
            guard model.showUnsaved else { throw Failure.check("Reload bypassed dirty draft confirmation") }
            await model.resolveUnsaved(save: false)
            await idle(model)
            guard !model.dirty, model.draft?.name == "Changed elsewhere", model.revision == 4 else {
                throw Failure.check("Deliberate reload did not load current head")
            }
            var invalidPattern = model.draft!
            let conditionID = invalidPattern.conditions.children[0].id
            invalidPattern.conditions.update(conditionID) { node in
                var predicate = node.predicateValue!
                predicate.field = .name
                predicate.operation = .regex
                predicate.text = "("
                node.content = .predicate(predicate)
            }
            model.update(invalidPattern, session: model.sessionID)
            let revisionBeforeCompile = model.revision
            guard !(await model.save()), model.dirty, model.revision == revisionBeforeCompile,
                model.compilerIssues.first?.code == "invalid_regex",
                model.compilerIssues.first?.node_id == conditionID
            else { throw Failure.check("Invalid pattern lost draft/revision or inline condition error") }
            var fixedPattern = model.draft!
            fixedPattern.conditions.update(conditionID) { node in
                var predicate = node.predicateValue!
                predicate.text = "invoice"
                node.content = .predicate(predicate)
            }
            model.update(fixedPattern, session: model.sessionID)
            guard model.compilerIssues.isEmpty, model.error == nil else { throw Failure.check("Editing retained stale compiler feedback") }
            model.discard()
            let scriptID = try await engine.listRules(folderID: folder.id).first {
                $0.name == ActionKind.script.rawValue
            }!.id
            model.select(scriptID)
            await idle(model)
            var scriptRule = model.draft!
            scriptRule.actions.steps[0].acknowledgeScript(true)
            model.update(scriptRule, session: model.sessionID)
            guard model.valid, await model.save() else {
                throw Failure.check("Loaded custom interpreter metadata did not allow configuration resave")
            }
            guard model.valid,
                model.draft?.actions.steps[0].script.arguments.map(\.id)
                    == scriptRule.actions.steps[0].script.arguments.map(\.id)
            else {
                throw Failure.check("Acknowledged Save reset script form evidence or stable argument identity")
            }
            await engine.shutdown()
            let reopened = EngineClient()
            _ = try await reopened.openStore(at: root.appendingPathComponent("data", isDirectory: true))
            guard try await reopened.rule(id: edit.id)?.definition.draft().name == "Changed elsewhere" else {
                throw Failure.check("Native restart lost saved rule")
            }
            guard try Data(contentsOf: sentinel) == Data("untouched".utf8),
                try Data(contentsOf: scriptURL) == Data("#!/bin/sh\nexit 0\n".utf8)
            else { throw Failure.check("Configuration changed fixture contents") }
            await reopened.shutdown()
            try fm.removeItem(at: root)
            print(
                "Native rule persistence passed: \(count) condition/action fixtures, paging, revisions, dirty/session guards, reopen; no file effects"
            )
        } catch {
            await engine.shutdown()
            FileHandle.standardError.write(
                Data(("Native rule persistence failed: \(error)\nFixture: \(root.path)\n").utf8))
            exit(1)
        }
    }
    @MainActor static func idle(_ model: LiveRuleModel) async {
        while model.pending { try? await Task.sleep(nanoseconds: 5_000_000) }
    }
    enum Failure: Error { case check(String) }
}

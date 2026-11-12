import Foundation

enum RuleCodingError: LocalizedError {
    case incompatible, invalidDraft, sampleLocation
    var errorDescription: String? {
        switch self {
        case .incompatible:
            return "This rule contains values this editor cannot represent. Its saved definition was not changed."
        case .invalidDraft: return "Correct the marked rule fields before saving."
        case .sampleLocation:
            return
                "Choose a real local location before saving this rule. Sample locations cannot be saved to your workspace."
        }
    }
}

// A lossless JSON boundary for the Rust schema, not a second evaluation engine.
// Integer cases keep byte thresholds above Double's exact range intact.
indirect enum RuleValue: Codable, Equatable {
    case object([String: RuleValue])
    case array([RuleValue])
    case string(String)
    case uint(UInt64)
    case int(Int64)
    case number(Double)
    case bool(Bool)
    case null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(UInt64.self) {
            self = .uint(v)
        } else if let v = try? c.decode(Int64.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([RuleValue].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: RuleValue].self))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .uint(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> RuleValue {
        if case .object(let v) = self { return v[key] ?? .null }
        return .null
    }
    func string() throws -> String {
        guard case .string(let v) = self else { throw RuleCodingError.incompatible }
        return v
    }
    func bool() throws -> Bool {
        guard case .bool(let v) = self else { throw RuleCodingError.incompatible }
        return v
    }
    func array() throws -> [RuleValue] {
        guard case .array(let v) = self else { throw RuleCodingError.incompatible }
        return v
    }
    func uint() throws -> UInt64 {
        guard case .uint(let v) = self else { throw RuleCodingError.incompatible }
        return v
    }
    func int() throws -> Int64 {
        if case .int(let v) = self { return v }
        if case .uint(let v) = self, let exact = Int64(exactly: v) { return exact }
        throw RuleCodingError.incompatible
    }
    func double() throws -> Double {
        switch self {
        case .number(let v): return v
        case .uint(let v): return Double(v)
        case .int(let v): return Double(v)
        default: throw RuleCodingError.incompatible
        }
    }
    func uuid() throws -> UUID {
        guard let v = UUID(uuidString: try string()) else { throw RuleCodingError.incompatible }
        return v
    }
    static func strings(_ values: [String]) -> Self { .array(values.map(Self.string)) }
    func strings() throws -> [String] { try array().map { try $0.string() } }
    func orderedLabels() -> Self {
        switch self {
        case .object(let values):
            return .object(values.mapValues { $0.orderedLabels() })
                .sortingLabelArray()
        case .array(let values): return .array(values.map { $0.orderedLabels() })
        default: return self
        }
    }
    private func sortingLabelArray() -> Self {
        guard case .object(var fields) = self, case .array(let items) = fields["labels"],
            let names = try? items.map({ try $0.string() })
        else { return self }
        fields["labels"] = .strings(names.sorted())
        return .object(fields)
    }
}

struct StoredRuleDefinition: Codable, Equatable {
    private var value: RuleValue
    init(draft: DemoRule) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.name.count <= 200,
            draft.conditions.validationIssues.isEmpty,
            draft.actions.issues(enabled: draft.enabled, conditions: draft.conditions).isEmpty
        else { throw RuleCodingError.invalidDraft }
        value = try Self.encodeDraft(draft)
    }
    func draft() throws -> DemoRule {
        guard try value["schema_version"].uint() == 1 else { throw RuleCodingError.incompatible }
        var rule = DemoRule(
            id: try value["id"].uuid(), name: try value["name"].string(), enabled: try value["enabled"].bool(),
            conditions: try ConditionDraftNode.read(value["conditions"]))
        rule.actions = .init(
            steps: try value["actions"].array().map(ActionDraft.read),
            behavior: try choice(value["behavior"], behaviors))
        // Reject unknown/unrepresentable options rather than silently dropping
        // them when a newer or externally created definition reaches the editor.
        let canonical = try JSONDecoder().decode(RuleValue.self, from: JSONEncoder().encode(Self.encodeDraft(rule)))
        guard canonical.orderedLabels() == value.orderedLabels() else { throw RuleCodingError.incompatible }
        return rule
    }
    private static func encodeDraft(_ rule: DemoRule) throws -> RuleValue {
        .object([
            "schema_version": .uint(1), "id": uuid(rule.id), "name": .string(rule.name), "enabled": .bool(rule.enabled),
            "conditions": try rule.conditions.wire(), "actions": .array(try rule.actions.steps.map { try $0.wire() }),
            "behavior": try encoded(rule.actions.behavior, behaviors),
        ])
    }
    init(from decoder: Decoder) throws { value = try RuleValue(from: decoder) }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    func matches(_ other: Self) throws -> Bool {
        func normalized(_ definition: Self) throws -> RuleValue {
            try JSONDecoder().decode(RuleValue.self, from: JSONEncoder().encode(definition)).orderedLabels()
        }
        return try normalized(self) == normalized(other)
    }
}

struct StoredRuleRecord: Decodable {
    var folder_id: String
    var revision: UInt64
    var definition: StoredRuleDefinition
}
struct StoredRuleSummary: Decodable, Identifiable {
    var id: UUID
    var revision: UInt64
    var name: String
    var enabled: Bool
    var condition_count: Int
    var action_count: Int
}
struct StoredRuleIssue: Decodable, Identifiable {
    var node_id: UUID?
    var id: String { "\(node_id?.uuidString ?? "rule"):\(path):\(code)" }
    var code: String
    var path: String
    var message: String
}

private func uuid(_ id: UUID) -> RuleValue { .string(id.uuidString.lowercased()) }
private func encoded<T: Hashable>(_ value: T, _ choices: [T: String]) throws -> RuleValue {
    guard let name = choices[value] else { throw RuleCodingError.incompatible }
    return .string(name)
}
private func choice<T: Hashable>(_ value: RuleValue, _ choices: [T: String]) throws -> T {
    let name = try value.string()
    guard let pair = choices.first(where: { $0.value == name }) else { throw RuleCodingError.incompatible }
    return pair.key
}
private let behaviors: [ActionRuleBehavior: String] = [.stop: "stop", .continueRules: "continue_rules"]
private let operators: [ConditionOperator: String] = [
    .isValue: "is", .isNot: "is_not", .contains: "contains", .notContains: "does_not_contain", .begins: "begins_with",
    .ends: "ends_with", .glob: "glob", .regex: "regex", .oneOf: "one_of", .notOneOf: "not_one_of", .empty: "is_empty",
    .equals: "equals", .less: "less_than", .greater: "greater_than", .between: "between", .before: "before",
    .after: "after", .onDate: "on_date", .dateRange: "date_range", .older: "older_than", .newer: "newer_than",
    .today: "today", .yesterday: "yesterday", .containsAny: "contains_any", .containsAll: "contains_all",
    .containsNone: "contains_none",
]
private let fields: [ConditionField: String] = [
    .name: "name", .extensionName: "extension", .kind: "kind", .size: "size", .date: "date", .tags: "tags",
    .label: "label", .text: "text",
]
private let kinds: [ConditionKind: String] = [
    .document: "document", .image: "image", .pdf: "pdf", .audio: "audio", .video: "video", .archive: "archive",
    .other: "other", .custom: "ut_type",
]
private let dates: [ConditionDateField: String] = [
    .created: "created", .modified: "modified", .opened: "last_opened", .added: "added_to_folder",
]
private let sources: [ContentSource: String] = [
    .embeddedOnly: "embedded_only", .embeddedThenOCR: "embedded_then_ocr", .forceOCR: "force_ocr",
]
private func named<T: RawRepresentable & CaseIterable & Hashable>(_ type: T.Type) -> [T: String]
where T.RawValue == String { Dictionary(uniqueKeysWithValues: T.allCases.map { ($0, $0.rawValue.lowercased()) }) }
private var labels: [ConditionLabel: String] { named(ConditionLabel.self) }
private var sizeUnits: [ConditionSizeUnit: String] { named(ConditionSizeUnit.self) }
private var ageUnits: [ConditionAgeUnit: String] { named(ConditionAgeUnit.self) }
private var gregorian: Calendar { Calendar(identifier: .gregorian) }
private func timestamp(_ date: Date) throws -> RuleValue {
    guard let v = Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded()) else {
        throw RuleCodingError.invalidDraft
    }
    return .int(v)
}
private func date(_ value: RuleValue) throws -> Date { Date(timeIntervalSince1970: Double(try value.int()) / 1000) }

extension ConditionDraftNode {
    fileprivate func wire() throws -> RuleValue {
        let expression: RuleValue
        switch content {
        case .group(let mode, let children):
            expression = .object([
                "type": .string(mode.rawValue.lowercased()), "children": .array(try children.map { try $0.wire() }),
            ])
        case .predicate(let p): expression = .object(["type": .string("predicate"), "predicate": try p.wire()])
        }
        return .object(["id": uuid(id), "expression": expression])
    }
    fileprivate static func read(_ value: RuleValue) throws -> Self {
        let e = value["expression"]
        let type = try e["type"].string()
        let content: ConditionDraftContent
        if type == "predicate" {
            content = .predicate(try ConditionPredicateDraft.read(e["predicate"]))
        } else {
            guard let mode = ConditionGroupMode.allCases.first(where: { $0.rawValue.lowercased() == type }) else {
                throw RuleCodingError.incompatible
            }
            content = .group(mode, try e["children"].array().map(Self.read))
        }
        return .init(id: try value["id"].uuid(), content: content)
    }
}
extension ConditionPredicateDraft {
    fileprivate func wire() throws -> RuleValue {
        var result = ["field": try StoredRule.wireField(field)]
        let op = try encoded(operation, operators)
        switch field {
        case .name:
            result.merge([
                "op": op, "value": .string(text), "scope": .string(nameScope == .stem ? "stem" : "filename"),
                "case_sensitive": .bool(caseSensitive),
            ]) { _, new in new }
        case .text:
            result.merge([
                "op": op, "value": .string(text), "source": try encoded(textSource, sources),
                "case_sensitive": .bool(caseSensitive),
            ]) { _, new in new }
        case .extensionName:
            var test = ["op": op]
            if operation != .empty {
                var seen = Set<String>()
                test["values"] = .strings(normalizedExtensions.filter { seen.insert($0).inserted })
            }
            result["test"] = .object(test)
        case .kind:
            var k = ["type": try encoded(kind, kinds)]
            if kind == .custom { k["identifier"] = .string(text) }
            result["op"] = op
            result["kind"] = .object(k)
        case .size:
            guard let lower = sizeUnit.bytes(from: text) else { throw RuleCodingError.invalidDraft }
            var test = ["op": op]
            if operation == .between {
                guard let upper = sizeUnit.bytes(from: upperText) else { throw RuleCodingError.invalidDraft }
                test["minimum"] = .uint(lower)
                test["maximum"] = .uint(upper)
            } else {
                test["bytes"] = .uint(lower)
            }
            result["unit"] = try encoded(sizeUnit, sizeUnits)
            result["test"] = .object(test)
        case .date:
            var test = ["op": op]
            switch operation {
            case .before, .after: test["timestamp_ms"] = try timestamp(startDate)
            case .onDate:
                let c = gregorian.dateComponents([.year, .month, .day], from: startDate)
                guard let y = c.year, let m = c.month, let d = c.day, y > 0, y <= 9999 else {
                    throw RuleCodingError.invalidDraft
                }
                test["date"] = .object(["year": .uint(UInt64(y)), "month": .uint(UInt64(m)), "day": .uint(UInt64(d))])
            case .dateRange:
                test["start_ms"] = try timestamp(startDate)
                test["end_ms"] = try timestamp(endDate)
            case .older, .newer:
                guard let n = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), n.isFinite, n >= 0 else {
                    throw RuleCodingError.invalidDraft
                }
                test["amount"] = .number(n)
                test["unit"] = try encoded(ageUnit, ageUnits)
            case .today, .yesterday: break
            default: throw RuleCodingError.invalidDraft
            }
            result["source"] = try encoded(dateField, dates)
            result["test"] = .object(test)
        case .tags:
            var test = ["op": op]
            if operation != .empty { test["names"] = .strings(tagNames) }
            result["case_sensitive"] = .bool(caseSensitive)
            result["test"] = .object(test)
        case .label:
            result["op"] = op
            result["labels"] = .array(
                try ConditionLabel.allCases.filter { self.labels.contains($0) }.map {
                    try encoded($0, StoredRule.labelChoices)
                })
        }
        return .object(result)
    }
    fileprivate static func read(_ v: RuleValue) throws -> Self {
        let f = try choice(v["field"], fields)
        let test = v["test"]
        var p = Self(field: f)
        p.operation = try choice(
            [ConditionField.extensionName, .size, .date, .tags].contains(f) ? test["op"] : v["op"], operators)
        switch f {
        case .name:
            p.text = try v["value"].string()
            p.caseSensitive = try v["case_sensitive"].bool()
            p.nameScope = try choice(v["scope"], [.filename: "filename", .stem: "stem"])
        case .text:
            p.text = try v["value"].string()
            p.caseSensitive = try v["case_sensitive"].bool()
            p.textSource = try choice(v["source"], sources)
        case .extensionName: if p.operation != .empty { p.text = try test["values"].strings().joined(separator: ", ") }
        case .kind:
            p.kind = try choice(v["kind"]["type"], kinds)
            if p.kind == .custom { p.text = try v["kind"]["identifier"].string() }
        case .size:
            p.sizeUnit = try choice(v["unit"], sizeUnits)
            if p.operation == .between {
                p.text = p.sizeUnit.display(try test["minimum"].uint())
                p.upperText = p.sizeUnit.display(try test["maximum"].uint())
            } else {
                p.text = p.sizeUnit.display(try test["bytes"].uint())
            }
        case .date:
            p.dateField = try choice(v["source"], dates)
            switch p.operation {
            case .before, .after: p.startDate = try date(test["timestamp_ms"])
            case .dateRange:
                p.startDate = try date(test["start_ms"])
                p.endDate = try date(test["end_ms"])
            case .onDate:
                let d = test["date"]
                let c = DateComponents(
                    year: Int(try d["year"].uint()), month: Int(try d["month"].uint()), day: Int(try d["day"].uint()),
                    hour: 12)
                guard let day = gregorian.date(from: c) else { throw RuleCodingError.incompatible }
                p.startDate = day
            case .older, .newer:
                p.text = String(try test["amount"].double())
                p.ageUnit = try choice(test["unit"], ageUnits)
            case .today, .yesterday: break
            default: throw RuleCodingError.incompatible
            }
        case .tags:
            p.caseSensitive = try v["case_sensitive"].bool()
            if p.operation != .empty { p.tagNames = try test["names"].strings() }
        case .label: p.labels = Set(try v["labels"].array().map { try choice($0, StoredRule.labelChoices) })
        }
        guard f.operators.contains(p.operation) else { throw RuleCodingError.incompatible }
        return p
    }
}
// Namespaced helpers avoid colliding with form properties named wire/labels.
private enum StoredRule {
    static func wireField(_ f: ConditionField) throws -> RuleValue { try encoded(f, fields) }
    static var labelChoices: [ConditionLabel: String] { labels }
}
extension ConditionSizeUnit {
    fileprivate func display(_ bytes: UInt64) -> String {
        let whole = bytes / multiplier
        var remainder = bytes % multiplier
        guard remainder != 0 else { return String(whole) }
        var fraction = ""
        while remainder != 0 {
            remainder *= 10
            fraction += String(remainder / multiplier)
            remainder %= multiplier
        }
        return "\(whole).\(fraction)"
    }
}

extension ActionLocationDraft {
    fileprivate func wire() throws -> RuleValue {
        guard !sample else { throw RuleCodingError.sampleLocation }
        guard isValid else { throw RuleCodingError.invalidDraft }
        return .object([
            "path_bytes_base64": .string(path.base64EncodedString()),
            "bookmark_base64": .string(bookmark.base64EncodedString()),
        ])
    }
    fileprivate static func read(_ v: RuleValue) throws -> Self {
        guard let path = Data(base64Encoded: try v["path_bytes_base64"].string()),
            let bookmark = Data(base64Encoded: try v["bookmark_base64"].string())
        else { throw RuleCodingError.incompatible }
        let result = Self(
            path: path, bookmark: bookmark,
            displayPath: (try? NativeFolderAccess.url(for: path).path) ?? "Local byte-path location")
        guard result.isValid else { throw RuleCodingError.incompatible }
        return result
    }
}
private func template(_ text: String, _ capture: UUID?) -> RuleValue {
    .object(["text": .string(text), "capture_condition_id": capture.map(uuid) ?? .null])
}
private func capture(_ v: RuleValue) throws -> UUID? {
    v["capture_condition_id"] == .null ? nil : try v["capture_condition_id"].uuid()
}
private let conflicts: [ActionConflict: String] = [.keepBoth: "keep_both", .skip: "skip", .ask: "ask"]
extension ActionDestinationDraft {
    fileprivate func wire(capture: UUID?) throws -> RuleValue {
        guard let root else { throw RuleCodingError.invalidDraft }
        return .object([
            "root": try root.wire(), "subfolder": template(subfolder, capture), "create_missing": .bool(createMissing),
            "conflict": try encoded(conflict, conflicts),
        ])
    }
    fileprivate static func read(_ v: RuleValue) throws -> Self {
        .init(
            root: try .read(v["root"]), subfolder: try v["subfolder"]["text"].string(),
            createMissing: try v["create_missing"].bool(), conflict: try choice(v["conflict"], conflicts))
    }
}
private let actionKinds: [ActionKind: String] = [
    .move: "move", .copy: "copy", .rename: "rename", .metadata: "metadata", .compress: "compress",
    .uncompress: "uncompress", .trash: "trash", .delete: "delete", .script: "script",
]
private let interpreters: [ActionInterpreter: String] = [
    .zsh: "zsh", .sh: "sh", .executable: "executable", .custom: "custom",
]
extension ActionDraft {
    fileprivate func wire() throws -> RuleValue {
        var a = ["type": try encoded(kind, actionKinds)]
        switch kind {
        case .move, .copy, .uncompress: a["destination"] = try destination.wire(capture: captureConditionID)
        case .compress:
            a["destination"] = try destination.wire(capture: captureConditionID)
            a["filename"] = template(filenameTemplate, archiveCaptureConditionID)
        case .rename:
            a["preserve_extension"] = .bool(preserveExtension)
            if renameMode == .template {
                a["rename"] = .object([
                    "mode": .string("template"), "template": template(filenameTemplate, captureConditionID),
                ])
            } else {
                a["rename"] = .object([
                    "mode": .string("replace"), "find": .string(find), "replacement": .string(replacement),
                    "regex": .bool(regex), "replace_all": .bool(replaceAll),
                ])
            }
        case .metadata:
            var tags = [
                "mode": try encoded(
                    tagsMode, [.unchanged: "unchanged", .add: "add", .remove: "remove", .replace: "replace"])
            ]
            if tagsMode != .unchanged { tags["names"] = .strings(tagNames) }
            if tagsMode == .replace { tags["acknowledged"] = .bool(replaceTagsAcknowledged) }
            var l = ["mode": try encoded(labelMode, [.unchanged: "unchanged", .set: "set", .clear: "clear"])]
            if labelMode == .set { l["color"] = try encoded(label, labels) }
            a["tags"] = .object(tags)
            a["label"] = .object(l)
        case .trash, .delete: break
        case .script:
            guard let file = script.file,
                let timeout = UInt64(script.timeout.trimmingCharacters(in: .whitespacesAndNewlines))
            else { throw RuleCodingError.invalidDraft }
            a["script"] = try file.wire()
            var interpreter = ["type": try encoded(script.interpreter, interpreters)]
            if script.interpreter == .custom {
                guard let executable = script.customInterpreter else { throw RuleCodingError.invalidDraft }
                interpreter["executable"] = try executable.wire()
            }
            a["interpreter"] = .object(interpreter)
            a["arguments"] = .strings(script.arguments.map(\.value))
            a["timeout_seconds"] = .uint(timeout)
            a["publish_output"] =
                script.publishOutput ? try script.destination.wire(capture: captureConditionID) : .null
        }
        return .object(["id": uuid(id), "action": .object(a)])
    }
    fileprivate static func read(_ v: RuleValue) throws -> Self {
        let a = v["action"]
        var step = Self(try choice(a["type"], actionKinds))
        step.id = try v["id"].uuid()
        switch step.kind {
        case .move, .copy, .uncompress, .compress:
            step.destination = try .read(a["destination"])
            step.captureConditionID = try capture(a["destination"]["subfolder"])
            if step.kind == .compress {
                step.filenameTemplate = try a["filename"]["text"].string()
                step.archiveCaptureConditionID = try capture(a["filename"])
            }
        case .rename:
            step.preserveExtension = try a["preserve_extension"].bool()
            let r = a["rename"]
            step.renameMode = try choice(r["mode"], [.template: "template", .replace: "replace"])
            if step.renameMode == .template {
                step.filenameTemplate = try r["template"]["text"].string()
                step.captureConditionID = try capture(r["template"])
            } else {
                step.find = try r["find"].string()
                step.replacement = try r["replacement"].string()
                step.regex = try r["regex"].bool()
                step.replaceAll = try r["replace_all"].bool()
            }
        case .metadata:
            step.tagsMode = try choice(
                a["tags"]["mode"], [.unchanged: "unchanged", .add: "add", .remove: "remove", .replace: "replace"])
            if step.tagsMode != .unchanged { step.tagNames = try a["tags"]["names"].strings() }
            if step.tagsMode == .replace { step.replaceTagsAcknowledged = try a["tags"]["acknowledged"].bool() }
            step.labelMode = try choice(a["label"]["mode"], [.unchanged: "unchanged", .set: "set", .clear: "clear"])
            if step.labelMode == .set { step.label = try choice(a["label"]["color"], labels) }
        case .trash, .delete: break
        case .script:
            step.script.file = try .read(a["script"])
            step.script.interpreter = try choice(a["interpreter"]["type"], interpreters)
            if step.script.interpreter == .custom {
                step.script.customInterpreter = try .read(a["interpreter"]["executable"])
            }
            step.script.arguments = try a["arguments"].strings().map { .init(value: $0) }
            step.script.timeout = String(try a["timeout_seconds"].uint())
            if a["publish_output"] != .null {
                step.script.publishOutput = true
                step.script.destination = try .read(a["publish_output"])
                step.captureConditionID = try capture(a["publish_output"]["subfolder"])
            }
        }
        // Script/delete approval and executable evidence are intentionally not
        // inferred from saved paths; future preflight must establish them.
        return step
    }
}

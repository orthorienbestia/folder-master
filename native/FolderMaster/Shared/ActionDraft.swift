import Foundation
import Darwin

enum ActionKind: String, CaseIterable, Identifiable {
    case move = "Move", copy = "Copy", rename = "Rename", metadata = "Tags / label", compress = "Compress ZIP", uncompress = "Uncompress ZIP", trash = "Trash", delete = "Permanently delete", script = "Custom script"
    var id: String { rawValue }
    var terminal: Bool { [.uncompress, .trash, .delete, .script].contains(self) }
}
enum ActionConflict: String, CaseIterable { case keepBoth = "Keep both", skip = "Skip", ask = "Ask" }
enum ActionRuleBehavior: String, CaseIterable { case stop = "Stop after match", continueRules = "Continue to next rule" }
enum ActionRenameMode: String, CaseIterable { case template = "Template", replace = "Find and replace" }
enum ActionTagMode: String, CaseIterable { case unchanged = "Leave unchanged", add = "Add", remove = "Remove", replace = "Replace" }
enum ActionLabelMode: String, CaseIterable { case unchanged = "Leave unchanged", set = "Set color", clear = "Clear" }
enum ActionInterpreter: String, CaseIterable { case zsh = "zsh", sh = "sh", executable = "Executable", custom = "Custom interpreter" }

struct ActionLocationDraft: Equatable, Sendable {
    var path: Data
    var bookmark: Data
    var displayPath: String
    var sample = false
    var wasExecutable = false
    static func sample(_ path: String) -> Self { .init(path: Data(path.utf8), bookmark: Data(), displayPath: path, sample: true) }
}
struct ActionDestinationDraft: Equatable {
    var root: ActionLocationDraft?
    var subfolder = ""
    var createMissing = true
    var conflict = ActionConflict.keepBoth
}
struct ActionArgumentDraft: Identifiable, Equatable { var id = UUID(); var value: String }
struct ActionScriptDraft: Equatable {
    var file: ActionLocationDraft?
    var interpreter = ActionInterpreter.zsh
    var customInterpreter: ActionLocationDraft?
    var arguments: [ActionArgumentDraft] = []
    var timeout = "30"
    var publishOutput = false
    var destination = ActionDestinationDraft()
}
struct ActionDraftIssue: Identifiable, Equatable {
    var actionID: UUID?
    var code: String
    var message: String
    var id: String { (actionID?.uuidString ?? "chain") + code }
}
struct ActionDraft: Identifiable, Equatable {
    var id = UUID()
    var kind: ActionKind
    var destination = ActionDestinationDraft()
    var renameMode = ActionRenameMode.template
    var filenameTemplate = "{stem}"
    var find = ""
    var replacement = ""
    var regex = false
    var replaceAll = false
    var preserveExtension = true
    var tagsMode = ActionTagMode.add
    var tagNames: [String] = []
    var tagEntry = ""
    var replaceTagsAcknowledged = false
    var labelMode = ActionLabelMode.unchanged
    var label = ConditionLabel.blue
    var deleteAcknowledged = false
    var script = ActionScriptDraft()
    var scriptAcknowledgement: ActionScriptDraft?
    var captureConditionID: UUID?
    var archiveCaptureConditionID: UUID?
    init(_ kind: ActionKind) {
        self.kind = kind
        if kind == .compress { filenameTemplate = "{stem}.zip" }
        if kind == .uncompress { destination.subfolder = "{stem}" }
    }
    var scriptAcknowledged: Bool { scriptAcknowledgement == script }
    mutating func acknowledgeScript(_ acknowledged: Bool) { scriptAcknowledgement = acknowledged ? script : nil }
    func issues(enabled: Bool, conditions: ConditionDraftNode) -> [ActionDraftIssue] {
        var result: [ActionDraftIssue] = []
        func add(_ code: String, _ message: String) { result.append(.init(actionID: id, code: code, message: message)) }
        func destinationIssues(_ value: ActionDestinationDraft) {
            if value.root?.isValid != true { add("destination", "Choose a local destination root or an explicitly labeled sample root.") }
            for message in ActionTemplateDraft.issues(value.subfolder, filename: false, allowEmpty: kind != .uncompress) { add("subfolder", message); break }
        }
        func templateIssues(_ text: String) {
            for message in ActionTemplateDraft.issues(text, filename: true) { add("template", message); break }
        }
        switch kind {
        case .move, .copy: destinationIssues(destination)
        case .rename:
            if renameMode == .template { templateIssues(filenameTemplate) }
            else {
                if find.isEmpty || find.contains("\0") { add("find", "Enter a nonempty find value without NUL characters.") }
                if replacement.contains("/") || replacement.contains("\0") { add("replacement", "Replacement text cannot contain a path separator or NUL.") }
            }
        case .metadata:
            if tagsMode != .unchanged && !tagEntry.isEmpty { add("pendingTag", "Add or clear the typed tag before saving.") }
            if tagsMode == .unchanged && labelMode == .unchanged { add("metadataChange", "Choose a tag or color-label change.") }
            if (tagsMode == .add || tagsMode == .remove) && tagNames.isEmpty && labelMode == .unchanged { add("tags", "Add at least one exact tag name or choose a label change.") }
            if tagsMode != .unchanged && tagNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.contains("\0") }) { add("tags", "Tag names cannot be empty or contain NUL.") }
            if tagsMode == .replace && !replaceTagsAcknowledged { add("replaceTags", "Confirm that replacement removes existing tag names. An empty replacement clears them.") }
            if labelMode == .set && label == .none { add("label", "Choose a color or use Clear.") }
        case .compress: destinationIssues(destination); templateIssues(filenameTemplate)
        case .uncompress: destinationIssues(destination)
        case .trash: break
        case .delete:
            if !deleteAcknowledged { add("deleteAcknowledgement", "Acknowledge that permanent deletion has no Undo and is not secure erase.") }
        case .script:
            if script.file?.isValid != true { add("script", "Choose a local script or executable.") }
            if script.interpreter == .executable && script.file?.wasExecutable != true { add("executable", "Choose a file verified executable at selection time. Permissions are rechecked by the future run preflight.") }
            if script.interpreter == .custom && (script.customInterpreter?.isValid != true || script.customInterpreter?.wasExecutable != true) { add("interpreter", "Choose a locally installed executable interpreter.") }
            let number = script.timeout.trimmingCharacters(in: .whitespacesAndNewlines)
            if number.isEmpty || !number.utf8.allSatisfy({ (48...57).contains($0) }) || !(1...600).contains(Int(number) ?? 0) { add("timeout", "Enter a whole number from 1 to 600 seconds.") }
            if script.arguments.contains(where: { $0.value.contains("\0") }) { add("arguments", "Arguments cannot contain NUL. Empty arguments and literal spaces are allowed.") }
            if script.publishOutput { destinationIssues(script.destination) }
            if !scriptAcknowledged { add("scriptAcknowledgement", "Acknowledge this sample configuration again after changing it. No script is approved for execution.") }
        }
        if enabled && (kind == .delete || kind == .script) { add("capability", "This build cannot enable delete or script rules: global capability and real approvals are unavailable.") }
        let templates: [String]
        switch kind {
        case .move, .copy, .uncompress: templates = [destination.subfolder]
        case .compress: templates = [destination.subfolder]
        case .rename: templates = renameMode == .template ? [filenameTemplate] : []
        case .script: templates = script.publishOutput ? [script.destination.subfolder] : []
        default: templates = []
        }
        if templates.contains(where: { $0.contains("{capture:") }) && !Self.captureSources(in: conditions).contains(where: { $0.id == captureConditionID }) {
            add("capture", "Choose an unambiguous regex condition under All groups for capture tokens. Named capture syntax still requires Rust validation.")
        }
        if kind == .compress && filenameTemplate.contains("{capture:") && !Self.captureSources(in: conditions).contains(where: { $0.id == archiveCaptureConditionID }) {
            add("archiveCapture", "Choose an unambiguous regex condition for archive filename captures.")
        }
        return result
    }
    static func captureSources(in node: ConditionDraftNode) -> [ConditionDraftNode] {
        switch node.content {
        case .predicate(let p): return p.operation == .regex ? [node] : []
        case .group(let mode, let children): return mode == .all ? children.flatMap { captureSources(in: $0) } : []
        }
    }
    func renewedIdentity(remappingCaptures: [UUID: UUID] = [:]) -> Self {
        var copy = self; copy.id = UUID()
        copy.script.arguments = script.arguments.map { .init(value: $0.value) }
        copy.deleteAcknowledged = false; copy.scriptAcknowledgement = nil
        copy.replaceTagsAcknowledged = false
        copy.captureConditionID = captureConditionID.flatMap { remappingCaptures[$0] }
        copy.archiveCaptureConditionID = archiveCaptureConditionID.flatMap { remappingCaptures[$0] }
        return copy
    }
}
struct ActionChainDraft: Equatable {
    var steps: [ActionDraft] = []
    var behavior = ActionRuleBehavior.stop
    var count: Int { steps.count }
    var isEmpty: Bool { steps.isEmpty }
    func issues(enabled: Bool, conditions: ConditionDraftNode) -> [ActionDraftIssue] {
        var result = steps.flatMap { $0.issues(enabled: enabled, conditions: conditions) }
        if steps.isEmpty || steps.count > 20 { result.append(.init(code: "actionCount", message: "Use between 1 and 20 actions.")) }
        if let index = steps.firstIndex(where: { $0.kind.terminal }) {
            if index != steps.count - 1 { result.append(.init(actionID: steps[index].id, code: "afterTerminal", message: "Terminal actions must be last. Move or remove the following actions.")) }
            if behavior != .stop { result.append(.init(code: "terminalContinue", message: "Terminal actions require Stop after match.")) }
        }
        return result
    }
    @discardableResult mutating func append(_ kind: ActionKind) -> UUID? {
        guard steps.count < 20, !steps.contains(where: { $0.kind.terminal }) else { return nil }
        let step = ActionDraft(kind); steps.append(step)
        if kind.terminal { behavior = .stop }
        return step.id
    }
    @discardableResult mutating func update(_ id: UUID, _ change: (inout ActionDraft) -> Void) -> Bool {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return false }
        let old = steps[index]
        change(&steps[index])
        if steps[index].tagNames != old.tagNames || steps[index].tagsMode != old.tagsMode { steps[index].replaceTagsAcknowledged = false }
        if steps.contains(where: { $0.kind.terminal }) { behavior = .stop }
        return true
    }
    @discardableResult mutating func remove(_ id: UUID) -> Bool {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return false }
        steps.remove(at: index); return true
    }
    @discardableResult mutating func move(_ id: UUID, by offset: Int) -> Bool {
        guard offset == -1 || offset == 1, let index = steps.firstIndex(where: { $0.id == id }), steps.indices.contains(index + offset) else { return false }
        steps.swapAt(index, index + offset); return true
    }
    func renewedIdentity(remappingCaptures: [UUID: UUID] = [:]) -> Self {
        Self(steps: steps.map { $0.renewedIdentity(remappingCaptures: remappingCaptures) }, behavior: behavior)
    }
}
enum ActionTemplateDraft {
    static func issues(_ text: String, filename: Bool, allowEmpty: Bool = false) -> [String] {
        if text.isEmpty { return allowEmpty ? [] : ["Enter a nonempty template."] }
        if text.contains("\0") || text.hasPrefix("/") || (filename && text.contains("/")) { return ["Use a contained relative template without NUL or filename separators."] }
        let components = text.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return ["Relative paths cannot contain empty, dot or parent components."] }
        var remainder = text[...]
        while !remainder.isEmpty {
            if remainder.first == "}" { return ["Unmatched closing token brace."] }
            if remainder.first != "{" { remainder.removeFirst(); continue }
            guard let end = remainder.firstIndex(of: "}") else { return ["Close each template token with a brace."] }
            let token = String(remainder[remainder.index(after: remainder.startIndex)..<end])
            let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            var valid = ["name", "stem", "ext"].contains(token)
            if parts.count == 2 {
                let option = String(parts[1])
                switch parts[0] {
                case "created", "modified", "now": valid = validDateFormat(option)
                case "counter": valid = !option.isEmpty && option.utf8.allSatisfy { (48...57).contains($0) } && (UInt32(option) ?? 0) > 0
                case "capture": valid = !option.isEmpty && option.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
                default: break
                }
            }
            if !valid { return ["Unknown token or unsupported token format: {" + token + "}."] }
            remainder = remainder[remainder.index(after: end)...]
        }
        return []
    }
    private static func validDateFormat(_ format: String) -> Bool {
        guard !format.isEmpty else { return false }
        var rest = format[...]
        while !rest.isEmpty {
            if rest.first == "-" || rest.first == "_" { rest.removeFirst(); continue }
            guard let token = ["yyyy", "MM", "dd", "HH", "mm", "ss"].first(where: { rest.hasPrefix($0) }) else { return false }
            rest = rest.dropFirst(token.count)
        }
        return true
    }
}

// These are location references for the form, not execution authorization.
extension ActionLocationDraft {
    var isValid: Bool { !path.isEmpty && path.first == 47 && !path.contains(0) && (sample || !bookmark.isEmpty) }
    static func file(_ url: URL, executable: Bool = false) throws -> Self {
        guard url.isFileURL else { throw ActionLocationError.file }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isAliasFileKey, .isSymbolicLinkKey, .volumeIsLocalKey])
        guard values.isRegularFile == true, values.isAliasFile != true, values.isSymbolicLink != true else { throw ActionLocationError.file }
        guard values.volumeIsLocal == true else { throw ActionLocationError.local }
        let readable = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return Darwin.access(path, executable ? R_OK | X_OK : R_OK) == 0
        }
        guard readable else { throw ActionLocationError.access }
        let wasExecutable = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return Darwin.access(path, X_OK) == 0
        }
        return Self(path: try NativeFolderAccess.pathData(for: url), bookmark: try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), displayPath: url.path, wasExecutable: wasExecutable)
    }
    static func folder(_ url: URL) throws -> Self {
        let candidate = try NativeFolderAccess.candidate(for: url)
        return Self(path: candidate.path, bookmark: candidate.bookmark, displayPath: url.path)
    }
}

enum ActionLocationError: LocalizedError {
    case file, local, access
    var errorDescription: String? {
        switch self {
        case .file: return "Choose a regular local file, rather than a directory, alias or symbolic link."
        case .local: return "Choose a file on a local mounted volume."
        case .access: return "The file is unavailable, unreadable or not executable when required."
        }
    }
}

struct ActionChooserRequest {
    private(set) var id: UUID?
    mutating func begin() -> UUID? {
        guard id == nil else { return nil }
        let next = UUID(); id = next; return next
    }
    mutating func invalidate() { id = nil }
    @discardableResult mutating func finish(_ request: UUID) -> Bool {
        guard id == request else { return false }
        id = nil; return true
    }
}

import SwiftUI
import AppKit

/// Native form state only. No action, script, template expansion or preview execution.
struct ActionChainEditor: View {
    @Binding var chain: ActionChainDraft
    let conditions: ConditionDraftNode
    let ruleEnabled: Bool
    var sample = true
    var compilerIssues: [StoredRuleIssue] = []
    @AppStorage("motionChoice") private var motion = MotionChoice.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @FocusState private var focus: ActionEditorFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Then do these actions").font(.headline)
            Text("\(chain.count) of 20 actions · \(sample ? "sample configuration only" : "saved configuration; execution unavailable")")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(chain.issues(enabled: ruleEnabled, conditions: conditions).filter { $0.actionID == nil }) { issue in
                ActionIssueLabel(message: issue.message)
            }
            ForEach(chain.steps) { step in
                ActionRowEditor(chain: $chain, actionID: step.id, conditions: conditions,
                                ruleEnabled: ruleEnabled, focus: $focus,
                                motion: MotionChoice(rawValue: motion) ?? .system, systemReduced: systemReduced, sample: sample, compilerIssues: compilerIssues)
            }
            Menu {
                ForEach(ActionKind.allCases) { kind in
                    Button(kind.rawValue) {
                        var id: UUID?
                        structure { id = chain.append(kind) }
                        if let id { focus = .kind(id) }
                    }
                }
            } label: { Label("Add Action", systemImage: "plus") }
                .disabled(chain.count >= 20 || chain.steps.contains { $0.kind.terminal })
                .help("Use at most 20 actions. Remove or change a terminal action before appending another.")
            Picker("Rule behavior", selection: $chain.behavior) {
                ForEach(ActionRuleBehavior.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.disabled(chain.steps.contains { $0.kind.terminal })
            Text(chain.steps.contains { $0.kind.terminal }
                 ? "A terminal action forces Stop after match. No following action is allowed."
                 : "Continue evaluates later rules against the current file; copy and ZIP outputs stay secondary.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func structure(_ change: () -> Void) {
        let duration = (MotionChoice(rawValue: motion) ?? .system).duration(systemReduced: systemReduced, normal: 0.18)
        if duration == 0 {
            var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
            withTransaction(transaction, change)
        } else { withAnimation(.easeInOut(duration: duration), change) }
    }
}

private enum ActionEditorFocus: Hashable {
    case kind(UUID), value(UUID, String), argument(UUID, UUID), up(UUID), down(UUID)
}
private struct ActionIssueLabel: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Blocking issue: \(message)")
    }
}
private enum ActionLocationTarget { case destination, script, interpreter, output }

private struct ActionRowEditor: View {
    @Binding var chain: ActionChainDraft
    let actionID: UUID
    let conditions: ConditionDraftNode
    let ruleEnabled: Bool
    let focus: FocusState<ActionEditorFocus?>.Binding
    let motion: MotionChoice
    let systemReduced: Bool
    let sample: Bool
    let compilerIssues: [StoredRuleIssue]
    @State private var expanded = true
    @State private var chooser = ActionChooserRequest()
    @State private var selectionError: String?
    private var current: ActionDraft? { chain.steps.first { $0.id == actionID } }
    private var position: Int { chain.steps.firstIndex { $0.id == actionID } ?? 0 }

    var body: some View {
        if let step = current {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Action", selection: kindBinding(step)) {
                                ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
                            }.focused(focus, equals: .kind(actionID))
                            actionControls(step)
                        }.padding(.top, 8)
                    } label: {
                        Text("\(position + 1). \(step.kind.rawValue)").fontWeight(.medium)
                    }
                    if let selectionError {
                        Label("Location selection failed: \(selectionError)", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if chooser.id != nil { ProgressView("Checking selected location…").controlSize(.small) }
                    ForEach(chain.issues(enabled: ruleEnabled, conditions: conditions).filter { $0.actionID == actionID }) { issue in
                        ActionIssueLabel(message: issue.message)
                    }
                    ForEach(compilerIssues.filter { $0.node_id == actionID }) { issue in
                        ActionIssueLabel(message: issue.message).id("compiler-\(issue.id)")
                    }
                    HStack {
                        Button { move(-1) } label: { Label("Up", systemImage: "arrow.up") }
                            .disabled(position == 0).focused(focus, equals: .up(actionID))
                            .accessibilityLabel("Move \(step.kind.rawValue) action up")
                        Button { move(1) } label: { Label("Down", systemImage: "arrow.down") }
                            .disabled(position + 1 == chain.count).focused(focus, equals: .down(actionID))
                            .accessibilityLabel("Move \(step.kind.rawValue) action down")
                        Spacer(minLength: 0)
                        Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Remove \(step.kind.rawValue) action")
                    }.controlSize(.small)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private func actionControls(_ step: ActionDraft) -> some View {
        switch step.kind {
        case .move, .copy:
            destinationControls(step.destination, target: .destination)
            capturePicker(step)
            Text(step.kind == .move ? "Move updates the current path. Leaving the watched scope finishes this rule's approved actions, then stops later rules."
                 : "Copy retains the source as the current file and records a separate output.")
                .font(.caption).foregroundStyle(.secondary)
        case .rename:
            Picker("Rename mode", selection: value(\.renameMode, fallback: step.renameMode)) {
                ForEach(ActionRenameMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if step.renameMode == .template {
                templateInput("Filename template", text: value(\.filenameTemplate, fallback: step.filenameTemplate))
                capturePicker(step)
            } else {
                input("Find", text: value(\.find, fallback: step.find))
                input("Replace with (may be empty)", text: value(\.replacement, fallback: step.replacement))
                Toggle("Use Rust regex", isOn: value(\.regex, fallback: step.regex)).toggleStyle(.checkbox)
                Toggle("Replace all occurrences", isOn: value(\.replaceAll, fallback: step.replaceAll)).toggleStyle(.checkbox)
                Text(sample ? "Literal find by default. This sample form does not compile regex or replacement captures." : "Literal find by default. Save checks Rust regex and replacement capture references locally.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Preserve extension", isOn: value(\.preserveExtension, fallback: step.preserveExtension)).toggleStyle(.checkbox)
            Text("With Preserve extension, enter a stem; the current extension is appended once during planning.")
                .font(.caption).foregroundStyle(.secondary)
        case .metadata: metadataControls(step)
        case .compress:
            Text("ZIP · originals retained · no password or encryption").font(.caption).foregroundStyle(.secondary)
            destinationControls(step.destination, target: .destination)
            capturePicker(step)
            templateInput("Archive filename template", text: value(\.filenameTemplate, fallback: step.filenameTemplate))
            capturePicker(step, archive: true)
        case .uncompress:
            Text("Terminal · ZIP only · retains the archive · creates a new output subfolder, never merges")
                .font(.caption).foregroundStyle(.secondary)
            destinationControls(step.destination, target: .destination, extraction: true)
            capturePicker(step)
            Text("Unsafe paths, links, encrypted entries and expansion-limit violations must be rejected by the future executor.")
                .font(.caption).foregroundStyle(.secondary)
        case .trash:
            Label("Terminal · system Trash", systemImage: "trash")
            Text("No permanent-delete fallback. Undo will require the actual returned Trash location and unchanged-item checks.")
                .font(.caption).foregroundStyle(.secondary)
        case .delete:
            Label("Terminal · no Undo · not secure erase", systemImage: "exclamationmark.triangle")
            Toggle("I understand permanent deletion is not recoverable through this app", isOn: value(\.deleteAcknowledged, fallback: step.deleteAcknowledged)).toggleStyle(.checkbox)
            Text("Configuration acknowledgement only. Delete rules cannot be enabled in this build; global capability and real per-rule approvals are not implemented.")
                .font(.caption).foregroundStyle(.secondary)
        case .script: scriptControls(step)
        }
    }

    private func destinationControls(_ destination: ActionDestinationDraft, target: ActionLocationTarget, extraction: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            location("Destination root", selection: destination.root, target: target)
            templateInput(extraction ? "New output subfolder (required)" : "Relative subfolder (optional)", text: destinationValue(target, \.subfolder, fallback: destination.subfolder))
            Toggle("Create missing subfolders", isOn: destinationValue(target, \.createMissing, fallback: destination.createMissing)).toggleStyle(.checkbox)
            Picker("If destination exists", selection: destinationValue(target, \.conflict, fallback: destination.conflict)) {
                ForEach(ActionConflict.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("No overwrite. Ask requires review during unattended runs. Other software may sync a selected cloud-synced location.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metadataControls(_ step: ActionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Tag change", selection: value(\.tagsMode, fallback: step.tagsMode)) {
                ForEach(ActionTagMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if step.tagsMode != .unchanged {
                ForEach(step.tagNames, id: \.self) { tag in
                    HStack {
                        Text(tag).textSelection(.enabled); Spacer(minLength: 0)
                        Button { edit { $0.tagNames.removeAll { $0 == tag } } } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Remove action tag \(tag)")
                    }
                }
                input("Exact tag name", text: value(\.tagEntry, fallback: step.tagEntry))
                    .onSubmit { addTag() }
                Button("Add Tag") { addTag() }.disabled(step.tagEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("One exact tag per entry; commas stay inside a name.").font(.caption).foregroundStyle(.secondary)
                if step.tagsMode == .replace {
                    Toggle("Replace existing tag names (empty list clears all)", isOn: value(\.replaceTagsAcknowledged, fallback: step.replaceTagsAcknowledged)).toggleStyle(.checkbox)
                }
            }
            Picker("Color label", selection: value(\.labelMode, fallback: step.labelMode)) {
                ForEach(ActionLabelMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if step.labelMode == .set {
                Picker("New color", selection: value(\.label, fallback: step.label)) {
                    ForEach(ConditionLabel.allCases.filter { $0 != .none }, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            Text("Finder may couple color labels and related tags. Real preview must report both; multiply-linked files will be blocked.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func scriptControls(_ step: ActionDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Terminal · restricted staged inputs · no network · no script Undo", systemImage: "terminal")
            location("Script or executable", selection: step.script.file, target: .script)
            Picker("Interpreter", selection: value(\.script.interpreter, fallback: step.script.interpreter)) {
                ForEach(ActionInterpreter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if step.script.interpreter == .custom { location("Custom executable interpreter", selection: step.script.customInterpreter, target: .interpreter) }
            input("Timeout in seconds (1–600)", text: value(\.script.timeout, fallback: step.script.timeout))
            Text("Literal arguments (in order)").font(.subheadline)
            ForEach(Array(step.script.arguments.enumerated()), id: \.element.id) { index, argument in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Argument \(index + 1) · empty is allowed").font(.caption).foregroundStyle(.secondary)
                        TextField("Literal argument", text: argumentValue(argument))
                            .textFieldStyle(.roundedBorder)
                            .focused(focus, equals: .argument(actionID, argument.id))
                            .accessibilityLabel("Literal argument \(index + 1)")
                    }
                    VStack {
                        Button { moveArgument(argument.id, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move argument \(index + 1) up")
                        Button { moveArgument(argument.id, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == step.script.arguments.count).accessibilityLabel("Move argument \(index + 1) down")
                    }
                    Button { removeArgument(argument.id) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove argument \(index + 1)")
                }
            }
            Button("Add Argument") {
                let argument = ActionArgumentDraft(value: "")
                edit { $0.script.arguments.append(argument) }
                focus.wrappedValue = .argument(actionID, argument.id)
            }
            Text("Spaces, commas and shell punctuation remain literal argv. Staged input/metadata/working/output paths will be supplied by the restricted service; original paths are never shell-interpolated.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Publish validated outputs", isOn: value(\.script.publishOutput, fallback: step.script.publishOutput)).toggleStyle(.checkbox)
            if step.script.publishOutput { destinationControls(step.script.destination, target: .output); capturePicker(step) }
            Toggle("Acknowledge this \(sample ? "sample " : "")script configuration", isOn: Binding(get: { current?.scriptAcknowledged ?? false }, set: { flag in edit { $0.acknowledgeScript(flag) } })).toggleStyle(.checkbox)
            Text("Changing invocation options resets this acknowledgement. No content hash or executable approval is granted. Scripts cannot be enabled until isolation and global/per-rule approval gates pass.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Test Script…") {}.disabled(true).help("Unavailable: restricted execution and real capability approvals are not integrated. Test Draft never runs scripts.")
        }
    }

    private func capturePicker(_ step: ActionDraft, archive: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(archive ? "Archive filename capture source" : "Capture source", selection: archive ? value(\.archiveCaptureConditionID, fallback: step.archiveCaptureConditionID) : value(\.captureConditionID, fallback: step.captureConditionID)) {
                Text("None").tag(UUID?.none)
                ForEach(ActionDraft.captureSources(in: conditions)) { node in
                    Text("\(node.predicateValue?.field.rawValue ?? "Regex"): \(node.predicateValue?.text ?? "")").tag(Optional(node.id))
                }
            }
            Text(sample ? "Needed for {capture:name}; only regex conditions under All groups are offered. This sample form does not compile named captures." : "Needed for {capture:name}; only regex conditions under All groups are offered. Save checks the selected source and named groups.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func input(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
                .focused(focus, equals: .value(actionID, title))
                .accessibilityLabel(title)
        }
    }
    private func templateInput(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            input(title, text: text)
            Menu("Append Token") {
                ForEach(["{name}", "{stem}", "{ext}", "{created:yyyy-MM-dd}", "{modified:yyyy-MM-dd}", "{now:yyyy-MM-dd}", "{counter:3}", "{capture:name}"], id: \.self) { token in
                    Button(token) { text.wrappedValue += token; focus.wrappedValue = .value(actionID, title) }
                }
            }.fixedSize()
            Text(sample ? "Date fields: yyyy, MM, dd, HH, mm, ss; separators - and _. Counter padding: 1–20 digits. This sample form does not compile templates." : "Date fields: yyyy, MM, dd, HH, mm, ss; separators - and _. Counter padding: 1–20 digits. Save checks syntax and capture references; Preview will check file-specific values.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func location(_ title: String, selection: ActionLocationDraft?, target: ActionLocationTarget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline)
            if let selection {
                Text(selection.displayPath).font(.caption).textSelection(.enabled).lineLimit(3)
                Label(selection.sample ? "Sample location · not selected on disk" : "Local location reference", systemImage: selection.sample ? "rectangle.dashed" : "folder")
                    .font(.caption).foregroundStyle(.secondary)
            } else { Text("No location selected").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Choose…") { choose(target) }.disabled(chooser.id != nil)
                if selection != nil { Button("Clear") { setLocation(nil, target: target) } }
            }
            Text("Choosing only reads location metadata and stores a bookmark in this draft. It creates no destination and executes nothing.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func choose(_ target: ActionLocationTarget) {
        guard let original = current, let request = chooser.begin() else { return }
        selectionError = nil
        let panel = NSOpenPanel()
        let directory = target == .destination || target == .output
        panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false; panel.resolvesAliases = false
        panel.message = "Choose a local \(directory ? "folder" : "file") for this \(sample ? "sample " : "")rule. Nothing will run or be written."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { chooser.finish(request); return }
            Task { @MainActor in
                do {
                    let selection = try await Task.detached(priority: .userInitiated) {
                        try directory ? ActionLocationDraft.folder(url) : ActionLocationDraft.file(url, executable: target == .interpreter || (target == .script && original.script.interpreter == .executable))
                    }.value
                    guard chooser.finish(request) else { return }
                    guard let now = current,
                          now.kind == original.kind, now.script.interpreter == original.script.interpreter,
                          now.script.publishOutput == original.script.publishOutput else { return }
                    setLocation(selection, target: target)
                } catch { if chooser.finish(request) { selectionError = error.localizedDescription } }
            }
        }
    }
    private func setLocation(_ location: ActionLocationDraft?, target: ActionLocationTarget) {
        chooser.invalidate(); selectionError = nil
        edit { step in
            switch target {
            case .destination: step.destination.root = location
            case .output: step.script.destination.root = location
            case .script: step.script.file = location
            case .interpreter: step.script.customInterpreter = location
            }
        }
    }
    private func value<T>(_ key: WritableKeyPath<ActionDraft, T>, fallback: T) -> Binding<T> {
        Binding(get: { current?[keyPath: key] ?? fallback }, set: { newValue in edit { $0[keyPath: key] = newValue } })
    }
    private func kindBinding(_ step: ActionDraft) -> Binding<ActionKind> {
        Binding(get: { current?.kind ?? step.kind }, set: { kind in
            edit { old in let id = old.id; old = ActionDraft(kind); old.id = id }
            selectionError = nil; chooser.invalidate(); focus.wrappedValue = .kind(actionID)
        })
    }
    private func destinationValue<T>(_ target: ActionLocationTarget, _ key: WritableKeyPath<ActionDestinationDraft, T>, fallback: T) -> Binding<T> {
        Binding(get: {
            guard let step = current else { return fallback }
            return (target == .output ? step.script.destination : step.destination)[keyPath: key]
        }, set: { newValue in
            edit { step in
                if target == .output { step.script.destination[keyPath: key] = newValue }
                else { step.destination[keyPath: key] = newValue }
            }
        })
    }
    private func argumentValue(_ argument: ActionArgumentDraft) -> Binding<String> {
        Binding(get: { current?.script.arguments.first { $0.id == argument.id }?.value ?? argument.value }, set: { newValue in
            edit { step in
                guard let index = step.script.arguments.firstIndex(where: { $0.id == argument.id }) else { return }
                step.script.arguments[index].value = newValue
            }
        })
    }
    private func moveArgument(_ id: UUID, by offset: Int) {
        edit { step in
            guard let index = step.script.arguments.firstIndex(where: { $0.id == id }), step.script.arguments.indices.contains(index + offset) else { return }
            step.script.arguments.swapAt(index, index + offset)
        }
        focus.wrappedValue = .argument(actionID, id)
    }
    private func removeArgument(_ id: UUID) {
        var next: UUID?
        edit { step in
            guard let index = step.script.arguments.firstIndex(where: { $0.id == id }) else { return }
            step.script.arguments.remove(at: index)
            if !step.script.arguments.isEmpty { next = step.script.arguments[min(index, step.script.arguments.count - 1)].id }
        }
        focus.wrappedValue = next.map { .argument(actionID, $0) } ?? .kind(actionID)
    }
    private func addTag() {
        edit { step in
            guard !step.tagEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if !step.tagNames.contains(step.tagEntry) { step.tagNames.append(step.tagEntry) }
            step.tagEntry = ""
        }
    }
    private func edit(_ change: (inout ActionDraft) -> Void) { chain.update(actionID, change) }
    private func structure(_ change: () -> Void) {
        let duration = motion.duration(systemReduced: systemReduced, normal: 0.18)
        if duration == 0 {
            var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
            withTransaction(transaction, change)
        } else { withAnimation(.easeInOut(duration: duration), change) }
    }
    private func move(_ offset: Int) {
        let before = focus.wrappedValue
        structure { chain.move(actionID, by: offset) }
        if (before == .up(actionID) && position == 0) || (before == .down(actionID) && position + 1 == chain.count) { focus.wrappedValue = .kind(actionID) }
        else { focus.wrappedValue = before }
    }
    private func remove() {
        let index = position
        structure { chain.remove(actionID) }
        if !chain.steps.isEmpty { focus.wrappedValue = .kind(chain.steps[min(index, chain.count - 1)].id) }
        else { focus.wrappedValue = nil }
    }
}

import SwiftUI

/// Synthetic form state only. This editor neither reads files nor evaluates rules.
struct ConditionTreeEditor: View {
    @Binding var root: ConditionDraftNode
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @AppStorage("motionChoice") private var motion = MotionChoice.system.rawValue
    @FocusState private var focus: ConditionEditorFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions").font(.headline)
            Text("Synthetic condition form — no actual rule evaluation or file access occurs.")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(root.predicateCount) of 50 conditions · up to 3 group levels")
                .font(.caption).foregroundStyle(.secondary)
            ConditionNodeEditor(root: $root, nodeID: root.id, focus: $focus,
                                motion: MotionChoice(rawValue: motion) ?? .system,
                                systemReduced: systemReduced)
            Text("Regex and glob use Rust syntax. Syntax is not validated in this form; matching and save-time syntax validation are not implemented here.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ConditionEditorFocus: Hashable {
    case group(UUID), field(UUID), value(UUID), upperValue(UUID), moveUp(UUID), moveDown(UUID)
}

private struct ConditionNodeEditor: View {
    @Binding var root: ConditionDraftNode
    let nodeID: UUID
    let focus: FocusState<ConditionEditorFocus?>.Binding
    let motion: MotionChoice
    let systemReduced: Bool
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        if let node = root.node(nodeID) {
            VStack(alignment: .leading, spacing: 8) {
                switch node.content {
                case .group(let mode, let children):
                    groupControls(mode: mode)
                    nodeIssues
                    ForEach(children) { child in
                        ConditionNodeEditor(root: $root, nodeID: child.id, focus: focus,
                                            motion: motion, systemReduced: systemReduced)
                            .padding(.leading, 8)
                            .transition(motion.allowsMovement(systemReduced: systemReduced)
                                        ? .opacity.combined(with: .move(edge: .top)) : .identity)
                    }
                    HStack(spacing: 8) {
                        Button("Add Condition") { addCondition() }
                            .disabled(root.predicateCount >= 50)
                            .help(root.predicateCount >= 50 ? "The form allows at most 50 conditions." : "Add a Name condition to this group.")
                        Button("Add Group") { addGroup() }
                            .disabled(root.predicateCount >= 50 || (root.groupLevel(nodeID) ?? 3) >= 3)
                            .help(root.predicateCount >= 50 ? "A new group includes a condition. The form allows at most 50 conditions."
                                  : (root.groupLevel(nodeID) ?? 3) >= 3 ? "The form allows at most 3 group levels."
                                  : "Add a nested All group with a Name condition.")
                    }
                case .predicate(let predicate):
                    predicateControls(predicate)
                    nodeIssues
                }
            }
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func groupControls(mode: ConditionGroupMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(nodeID == root.id ? "Root group" : "Group", selection: groupMode(fallback: mode)) {
                ForEach(ConditionGroupMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .focused(focus, equals: .group(nodeID))
            Text(groupExplanation(mode)).font(.caption).foregroundStyle(.secondary)
            if nodeID != root.id { rowActions(label: "group") }
        }
    }

    private func groupExplanation(_ mode: ConditionGroupMode) -> String {
        switch mode {
        case .all: return "All conditions must match. Unavailable data remains Unknown."
        case .any: return "Any condition may match. Unavailable data remains Unknown unless another condition matches."
        case .none: return "No condition may match. Unknown data does not become a match by negation."
        }
    }

    private func predicateControls(_ predicate: ConditionPredicateDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Field", selection: fieldBinding(fallback: predicate.field)) {
                ForEach(ConditionField.allCases) { Text($0.rawValue).tag($0) }
            }
            .focused(focus, equals: .field(nodeID))
            Picker("Operator", selection: value(\.operation, fallback: predicate.operation)) {
                ForEach(predicate.field.operators) { Text($0.rawValue).tag($0) }
            }
            predicateValues(predicate)
            if nodeID != root.id { rowActions(label: "\(predicate.field.rawValue) condition") }
        }
    }

    @ViewBuilder private func predicateValues(_ predicate: ConditionPredicateDraft) -> some View {
        switch predicate.field {
        case .name:
            textInput("Value", keyPath: \.text, fallback: predicate.text)
            Picker("Name scope", selection: value(\.nameScope, fallback: predicate.nameScope)) {
                ForEach(ConditionNameScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            caseControl(predicate)
            if predicate.operation == .regex || predicate.operation == .glob {
                Text("Rust \(predicate.operation.rawValue) syntax is not checked here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .extensionName:
            if predicate.operation != .empty {
                textInput("Extensions, separated by commas", keyPath: \.text, fallback: predicate.text)
                Text("Normalized: \(predicate.normalizedExtensions.map { $0.isEmpty ? "(empty)" : $0 }.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Final extension only: tar.gz uses gz. Leading dots and letter case are normalized.")
                .font(.caption).foregroundStyle(.secondary)
        case .kind:
            Picker("Kind", selection: value(\.kind, fallback: predicate.kind)) {
                ForEach(ConditionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .focused(focus, equals: .value(nodeID))
            if predicate.kind == .custom {
                textInput("UTType identifier", keyPath: \.text, fallback: predicate.text, receivesValueFocus: false)
                Text("For example, public.jpeg. Matching uses platform type conformance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .size:
            textInput(predicate.operation == .between ? "Minimum size" : "Size", keyPath: \.text, fallback: predicate.text)
            if predicate.operation == .between {
                textInput("Maximum size", keyPath: \.upperText, fallback: predicate.upperText, receivesValueFocus: false)
            }
            Picker("Size unit", selection: value(\.sizeUnit, fallback: predicate.sizeUnit)) {
                ForEach(ConditionSizeUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Text("Nonnegative values must convert to whole bytes. Range endpoints are inclusive.")
                .font(.caption).foregroundStyle(.secondary)
        case .date:
            dateControls(predicate)
        case .tags:
            tagControls(predicate)
        case .label:
            Text("Labels").font(.subheadline)
            ForEach(ConditionLabel.allCases, id: \.self) { label in
                if label == .none {
                    Toggle(label.rawValue, isOn: labelBinding(label))
                        .toggleStyle(.checkbox).focused(focus, equals: .value(nodeID))
                } else {
                    Toggle(label.rawValue, isOn: labelBinding(label)).toggleStyle(.checkbox)
                }
            }
            Text("Matches the Finder color label rather than tag names; related color tags may also be present. None requires a successfully read no-label state.")
                .font(.caption).foregroundStyle(.secondary)
        case .text:
            textInput(predicate.operation == .regex ? "Rust regex" : "Literal text", keyPath: \.text, fallback: predicate.text)
            caseControl(predicate)
            Picker("Content source", selection: value(\.textSource, fallback: predicate.textSource)) {
                Text("Embedded/text only").tag(ContentSource.embeddedOnly)
                Text("Embedded, then OCR if needed").tag(ContentSource.embeddedThenOCR)
                Text("Force OCR").tag(ContentSource.forceOCR)
            }
            Text("Partial extraction can prove a literal match. Regex and absence require complete extraction; otherwise the result is Unknown. Failed extraction is Unknown.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dateControls(_ predicate: ConditionPredicateDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Date source", selection: value(\.dateField, fallback: predicate.dateField)) {
                ForEach(ConditionDateField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            switch predicate.operation {
            case .older, .newer:
                textInput("Elapsed age", keyPath: \.text, fallback: predicate.text)
                Picker("Age unit", selection: value(\.ageUnit, fallback: predicate.ageUnit)) {
                    ForEach(ConditionAgeUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text("Elapsed days are 24-hour durations; older/newer comparisons are strict.")
                    .font(.caption).foregroundStyle(.secondary)
            case .today, .yesterday:
                Text("\(predicate.operation.rawValue) uses the current calendar day in the timezone shown below.")
                    .font(.caption).foregroundStyle(.secondary)
            case .onDate:
                DatePicker("Calendar date", selection: value(\.startDate, fallback: predicate.startDate), displayedComponents: .date)
                    .focused(focus, equals: .value(nodeID))
            case .dateRange:
                DatePicker("From (inclusive)", selection: value(\.startDate, fallback: predicate.startDate), displayedComponents: [.date, .hourAndMinute])
                    .focused(focus, equals: .value(nodeID))
                DatePicker("Through (inclusive)", selection: value(\.endDate, fallback: predicate.endDate), displayedComponents: [.date, .hourAndMinute])
                    .focused(focus, equals: .upperValue(nodeID))
            default:
                DatePicker("Date and time", selection: value(\.startDate, fallback: predicate.startDate), displayedComponents: [.date, .hourAndMinute])
                    .focused(focus, equals: .value(nodeID))
                Text("Before and after are strict comparisons.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Timezone: \(timeZone.identifier)").font(.caption).foregroundStyle(.secondary)
            Text("Unavailable metadata is Unknown. Added to folder never falls back to Created; Last opened is best-effort metadata, not an access audit.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tagControls(_ predicate: ConditionPredicateDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if predicate.operation != .empty {
                ForEach(predicate.tagNames, id: \.self) { tag in
                    HStack(spacing: 8) {
                        Text(tag).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { editPredicate { $0.tagNames.removeAll { $0 == tag } } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
                TextField("Exact tag name", text: value(\.tagEntry, fallback: predicate.tagEntry))
                    .textFieldStyle(.roundedBorder)
                    .focused(focus, equals: .value(nodeID))
                    .accessibilityLabel("Exact tag name")
                    .onSubmit { addTag() }
                Button("Add Tag") { addTag() }
                    .disabled(predicate.tagEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Add one exact name at a time. A comma stays inside the tag name.")
                    .font(.caption).foregroundStyle(.secondary)
                caseControl(predicate)
            }
            Text("No tags is distinct from a metadata read failure, which is Unknown.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func textInput(_ title: String, keyPath: WritableKeyPath<ConditionPredicateDraft, String>, fallback: String,
                           receivesValueFocus: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: value(keyPath, fallback: fallback))
                .textFieldStyle(.roundedBorder)
                .focused(focus, equals: receivesValueFocus ? .value(nodeID) : .upperValue(nodeID))
                .accessibilityLabel(title)
        }
    }

    private func caseControl(_ predicate: ConditionPredicateDraft) -> some View {
        Toggle("Case sensitive", isOn: value(\.caseSensitive, fallback: predicate.caseSensitive))
            .toggleStyle(.checkbox)
    }

    private var nodeIssues: some View {
        ForEach(root.validationIssues.filter { $0.nodeID == nodeID }) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Blocking issue: \(issue.message)")
        }
    }

    private func rowActions(label: String) -> some View {
        let siblings = root.siblings(of: nodeID)
        let index = siblings.firstIndex { $0.id == nodeID }
        return HStack(spacing: 8) {
            Button { move(by: -1) } label: { Label("Up", systemImage: "arrow.up") }
                .disabled(index == nil || index == 0)
                .focused(focus, equals: .moveUp(nodeID))
                .accessibilityLabel("Move \(label) up")
            Button { move(by: 1) } label: { Label("Down", systemImage: "arrow.down") }
                .disabled(index == nil || index == siblings.count - 1)
                .focused(focus, equals: .moveDown(nodeID))
                .accessibilityLabel("Move \(label) down")
            Spacer(minLength: 0)
            Button(role: .destructive) { remove() } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Remove \(label)")
            .help("Remove this \(label) from the draft only.")
        }
        .controlSize(.small)
    }

    // Every setter resolves the current node by UUID. A removed row's stale
    // binding cannot replace a sibling or reintroduce its captured snapshot.
    private func value<T>(_ keyPath: WritableKeyPath<ConditionPredicateDraft, T>, fallback: T) -> Binding<T> {
        Binding(get: { root.node(nodeID)?.predicateValue?[keyPath: keyPath] ?? fallback },
                set: { newValue in editPredicate { $0[keyPath: keyPath] = newValue } })
    }

    private func editPredicate(_ edit: (inout ConditionPredicateDraft) -> Void) {
        root.update(nodeID) { node in
            guard var predicate = node.predicateValue else { return }
            edit(&predicate)
            node.content = .predicate(predicate)
        }
    }

    private func fieldBinding(fallback: ConditionField) -> Binding<ConditionField> {
        Binding(get: { root.node(nodeID)?.predicateValue?.field ?? fallback }, set: { field in
            guard root.node(nodeID)?.predicateValue != nil else { return }
            root.update(nodeID) { $0.content = .predicate(ConditionPredicateDraft(field: field)) }
            focus.wrappedValue = .value(nodeID)
        })
    }

    private func groupMode(fallback: ConditionGroupMode) -> Binding<ConditionGroupMode> {
        Binding(get: {
            if let node = root.node(nodeID), case .group(let mode, _) = node.content { return mode }
            return fallback
        }, set: { mode in
            root.update(nodeID) { node in
                guard case .group(_, let children) = node.content else { return }
                node.content = .group(mode, children)
            }
        })
    }

    private func labelBinding(_ label: ConditionLabel) -> Binding<Bool> {
        Binding(get: { root.node(nodeID)?.predicateValue?.labels.contains(label) ?? false }, set: { selected in
            editPredicate { predicate in
                if selected { predicate.labels.insert(label) } else { predicate.labels.remove(label) }
            }
        })
    }

    private func addTag() {
        editPredicate { predicate in
            let tag = predicate.tagEntry
            guard !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if !predicate.tagNames.contains(tag) { predicate.tagNames.append(tag) }
            predicate.tagEntry = ""
        }
    }

    private func changeStructure(_ change: () -> Void) {
        if motion.allowsMovement(systemReduced: systemReduced) {
            withAnimation(.easeInOut(duration: motion.duration(systemReduced: systemReduced, normal: 0.18)), change)
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, change)
        }
    }

    private func addCondition() {
        var added: UUID?
        changeStructure { added = root.addPredicate(to: nodeID) }
        if let added { focus.wrappedValue = .value(added) }
    }

    private func addGroup() {
        var added: UUID?
        changeStructure { added = root.addGroup(to: nodeID) }
        if let added { focus.wrappedValue = .group(added) }
    }

    private func remove() {
        guard nodeID != root.id else { return }
        let target = root.focusAfterRemoving(nodeID)
        var removed = false
        changeStructure { removed = root.remove(nodeID) }
        guard removed else { return }
        if let target, let node = root.node(target) {
            focus.wrappedValue = defaultFocus(for: node)
        } else { focus.wrappedValue = nil }
    }

    private func move(by offset: Int) {
        let previousFocus = focus.wrappedValue
        changeStructure { root.move(nodeID, by: offset) }
        let siblings = root.siblings(of: nodeID)
        if (previousFocus == .moveUp(nodeID) && siblings.first?.id == nodeID)
            || (previousFocus == .moveDown(nodeID) && siblings.last?.id == nodeID) {
            if let node = root.node(nodeID) { focus.wrappedValue = defaultFocus(for: node) }
        } else { focus.wrappedValue = previousFocus }
    }

    private func defaultFocus(for node: ConditionDraftNode) -> ConditionEditorFocus {
        guard let predicate = node.predicateValue else { return .group(node.id) }
        let hasNoValueControl = (predicate.field == .extensionName || predicate.field == .tags) && predicate.operation == .empty
            || predicate.field == .date && (predicate.operation == .today || predicate.operation == .yesterday)
        return hasNoValueControl ? .field(node.id) : .value(node.id)
    }
}

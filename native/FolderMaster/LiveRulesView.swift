import SwiftUI

struct LiveRulesView: View {
    @ObservedObject var model: LiveRuleModel
    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Reload Saved") { model.reload() }.disabled(model.pending)
                    Button("Dismiss") { model.error = nil }
                }.font(.callout).padding(12).background(.yellow.opacity(0.10))
            }
            if model.pending && model.draft == nil {
                ProgressView("Loading saved rules…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.summaries.isEmpty && model.draft == nil {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "No rules yet", systemImage: "slider.horizontal.3",
                        description: Text(
                            "Build a disabled rule, then save it locally. Saving never processes existing files."))
                    Button("New Rule") { model.create() }.buttonStyle(.borderedProminent).disabled(
                        !model.loaded || model.pending)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Rules").font(.headline)
                            Spacer()
                            Button {
                                model.create()
                            } label: {
                                Label("New Rule", systemImage: "plus").labelStyle(.iconOnly)
                            }
                        }.padding(16)
                        Divider()
                        List(selection: Binding(get: { model.selectedID }, set: model.select)) {
                            ForEach(model.summaries) { rule in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(rule.name).fontWeight(.medium)
                                    Text(
                                        "Revision \(rule.revision) · \(rule.condition_count) conditions · \(rule.action_count) actions"
                                    ).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 6).tag(rule.id)
                            }
                            if model.isNew, let draft = model.draft {
                                Label(draft.name, systemImage: "pencil").tag(draft.id)
                            }
                        }.disabled(model.pending)
                    }.frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
                    LiveRuleEditor(model: model).frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .confirmationDialog("Save changes to this rule?", isPresented: $model.showUnsaved, titleVisibility: .visible) {
            Button("Save") { Task { await model.resolveUnsaved(save: true) } }.disabled(!model.valid)
            Button("Discard Changes", role: .destructive) { Task { await model.resolveUnsaved(save: false) } }
            Button("Keep Editing", role: .cancel) { model.keepEditing() }
        } message: {
            Text("Changes are stored locally only after the engine confirms the save.")
        }
    }
}

private struct LiveRuleEditor: View {
    @ObservedObject var model: LiveRuleModel
    @FocusState private var nameFocused: Bool
    private func edit(_ session: UUID, _ change: (inout DemoRule) -> Void) {
        guard var draft = model.draft else { return }
        change(&draft)
        model.update(draft, session: session)
    }
    var body: some View {
        if let draft = model.draft {
            let session = model.sessionID
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rule details").font(.headline)
                        Text(model.dirty ? "Unsaved changes" : "Saved revision \(model.revision ?? 0)").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        "Enabled configuration",
                        isOn: Binding(
                            get: { model.draft?.enabled ?? false },
                            set: { value in edit(session) { $0.enabled = value } })
                    )
                    .toggleStyle(.switch).controlSize(.small).help(
                        "This saves the rule's future enabled state. File automation remains unavailable in this build."
                    )
                }.padding(20)
                Divider()
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name").font(.subheadline.weight(.medium))
                                TextField(
                                    "Rule name",
                                    text: Binding(
                                        get: { model.draft?.name ?? "" },
                                        set: { name in edit(session) { $0.name = name } })
                                )
                                .textFieldStyle(.roundedBorder).focused($nameFocused).accessibilityLabel("Rule name")
                                if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || draft.name.count > 200
                                {
                                    Text("Enter a name of 1–200 characters.").font(.caption).foregroundStyle(.red)
                                }
                            }.id("live-rule-top")
                            ConditionTreeEditor(
                                root: Binding(
                                    get: { model.draft?.conditions ?? draft.conditions },
                                    set: { conditions in edit(session) { $0.conditions = conditions } }), sample: false, compilerIssues: model.compilerIssues)
                            Divider()
                            ActionChainEditor(
                                chain: Binding(
                                    get: { model.draft?.actions ?? draft.actions },
                                    set: { actions in edit(session) { $0.actions = actions } }),
                                conditions: draft.conditions, ruleEnabled: draft.enabled, sample: false, compilerIssues: model.compilerIssues)
                            Label(
                                "Rules are saved locally. Preview, matching, watching and file actions are not available yet.",
                                systemImage: "info.circle"
                            ).font(.caption).foregroundStyle(.secondary)
                        }.padding(20)
                    }.onChange(of: model.compilerIssues.map(\.id)) { _, _ in
                        if let first = model.compilerIssues.first {
                            scroll.scrollTo("compiler-\(first.id)", anchor: .center)
                        }
                    }.onChange(of: draft.id, initial: true) { _, _ in
                        scroll.scrollTo("live-rule-top", anchor: .top)
                        nameFocused = model.isNew
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if !model.valid {
                        Label("Correct the marked fields before saving.", systemImage: "exclamationmark.circle").font(
                            .caption
                        ).foregroundStyle(.red)
                    }
                    HStack {
                        if model.pending {
                            ProgressView().controlSize(.small)
                            Text("Saving or loading…").font(.caption)
                        } else if let revision = model.savedRevision {
                            Label("Saved locally · revision \(revision)", systemImage: "checkmark.circle").font(
                                .caption
                            ).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Discard") { model.discard() }.disabled(!model.dirty)
                        Button("Save Rule") { Task { await model.save() } }.buttonStyle(.borderedProminent).disabled(
                            !model.dirty || !model.valid)
                    }
                }.padding(16)
            }.disabled(model.pending)
        } else {
            ContentUnavailableView(
                "Select a rule", systemImage: "slider.horizontal.3",
                description: Text("Choose a saved rule or create a new one."))
        }
    }
}

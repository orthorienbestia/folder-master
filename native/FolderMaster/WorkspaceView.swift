import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Group {
            if model.demo { DemoWorkspaceView(model: model) }
            else { PersistentWorkspaceView(model: model) }
        }
        .disabled(model.quitPending)
        .overlay(alignment: .bottom) {
            if model.quitPending && (model.folderPending || model.enginePending || model.workspaceConnecting) {
                HStack { ProgressView().controlSize(.small); Text("Finishing settings update before quitting…") }
                    .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(16)
            }
        }
    }
}

struct DemoWorkspaceView: View {
    @ObservedObject var model: AppModel
    @AppStorage("motionChoice") private var motion = MotionChoice.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    private var animation: Animation? {
        let duration = (MotionChoice(rawValue: motion) ?? .system).duration(systemReduced: systemReduced, normal: 0.18)
        return duration == 0 ? nil : .easeInOut(duration: duration)
    }
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                if model.demo { demoBanner }
                if let error = model.error {
                    HStack { Label(error, systemImage: "exclamationmark.triangle"); Spacer(); Button("Dismiss") { model.error = nil } }
                        .padding(12).background(.yellow.opacity(0.12))
                }
                switch model.destination {
                case .history: HistoryView(model: model)
                case .folder: folderContent
                case nil: welcome
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "cpu").foregroundStyle(.secondary)
                    Text(model.engineStatus)
                    Spacer()
                    Text("Foundation build · no file actions").foregroundStyle(.secondary)
                }
                .font(.caption).padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
        .toolbar {
            if model.demo {
                ToolbarItemGroup {
                    Button { model.presentPreview() } label: { Label("Preview", systemImage: "eye") }
                        .help("Preview synthetic files; no folders are read")
                    Button { model.presentPreview() } label: { Label("Simulate Run", systemImage: "play") }
                }
            }
        }
        .sheet(isPresented: $model.showPreview) { PreviewView(model: model) }
        .confirmationDialog("Save changes to this demo rule?", isPresented: $model.showUnsaved, titleVisibility: .visible) {
            Button("Save") { model.resolveUnsaved(save: true) }.disabled(!model.validDraft)
            Button("Discard Changes", role: .destructive) { model.resolveUnsaved(save: false) }
            Button("Keep Editing", role: .cancel) { }
        } message: { Text("Changes are stored in this demo session only. Your files are never changed.") }
        .animation(animation, value: model.destination)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.destination) {
                Section("Watched folders") {
                    if model.folders.isEmpty { Text("No folders yet").foregroundStyle(.secondary) }
                    ForEach(model.folders) { folder in
                        Label(folder.name, systemImage: folder.symbol).tag(WorkspaceDestination.folder(folder.id))
                    }
                }
                Section {
                    Label("History", systemImage: "clock.arrow.circlepath").tag(WorkspaceDestination.history)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("Local by design", systemImage: "lock.shield").font(.callout.weight(.medium))
                Text("Rules and OCR are designed to stay on your Mac.").font(.caption).foregroundStyle(.secondary)
                SettingsLink { Label("Settings", systemImage: "gearshape") }.buttonStyle(.plain)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "testtube.2")
            Text("Interactive experience preview").fontWeight(.medium)
            Text("Synthetic folders and files. Nothing is read or changed.").foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Leave Demo") { model.demo = false }
                .help("Return to your saved folders; the sample session does not change their configuration")
        }
        .font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
        .background(.tint.opacity(0.08))
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray.2.fill").font(.system(size: 54, weight: .light)).foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("A place for every file.").font(.largeTitle.weight(.semibold))
                Text("Your folders. Your rules. Always on your Mac.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("folder.badge.gearshape", "Watch the folders you choose", "Create rules for names, dates, tags, content and more.")
                feature("eye", "See every change before it happens", "Understand matches and destinations in a dry-run preview.")
                feature("arrow.uturn.backward", "Stay in control", "Pause from the menu bar. Inspect history and supported undo.")
            }.frame(width: 440)
            Button("Explore Interactive Preview") { model.exploreDemo() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("Development foundation — real folder automation is coming next.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var folderContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rules").font(.headline)
                        Text("Evaluated from top to bottom").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.addRule() } label: { Image(systemName: "plus") }.help("New demo rule")
                }.padding(16)
                Divider()
                List(selection: Binding(get: { model.selectedRuleID }, set: { model.selectRule($0) })) {
                    ForEach(model.experience.rules) { rule in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle").foregroundStyle(rule.enabled ? Color.accentColor : .secondary)
                                .accessibilityLabel(rule.enabled ? "Enabled demo rule" : "Disabled demo rule")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(rule.name).fontWeight(.medium)
                                Text("\(rule.conditions.count) conditions · \(rule.actions.count) actions").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 7).tag(rule.id)
                        .contextMenu { Button("Duplicate as Disabled") { model.experience.duplicateRule(rule.id) } }
                    }
                }
                HStack { Text("First matching rule wins").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(12)
            }.frame(minWidth: 230, idealWidth: 260, maxWidth: 320)
            RuleEditorView(model: model).frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct RuleEditorView: View {
    @ObservedObject var model: AppModel
    @AppStorage("motionChoice") private var motion = MotionChoice.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    private func edit(_ change: (inout DemoRule) -> Void) {
        guard var draft = model.draft else { return }
        change(&draft); model.draft = draft; model.savedFeedback = false
    }
    private func mutate(_ change: (inout DemoRule) -> Void) {
        let duration = (MotionChoice(rawValue: motion) ?? .system).duration(systemReduced: systemReduced, normal: 0.18)
        withAnimation(duration == 0 ? nil : .easeInOut(duration: duration)) { edit(change) }
    }
    var body: some View {
        if let draft = model.draft {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rule details").font(.headline)
                        Text(model.dirty ? "Unsaved demo changes" : "Demo rule · session only").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding(get: { model.draft?.enabled ?? false }, set: { value in edit { $0.enabled = value } })).toggleStyle(.switch).controlSize(.small)
                }.padding(20)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name").font(.subheadline.weight(.medium))
                            TextField("Rule name", text: Binding(get: { model.draft?.name ?? "" }, set: { value in edit { $0.name = value } }))
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("Match all of these conditions").font(.headline); Spacer() }
                            ForEach(Array(draft.conditions.enumerated()), id: \.offset) { index, condition in
                                HStack {
                                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                                    TextField("Condition", text: Binding(get: { model.draft?.conditions[safe: index] ?? "" }, set: { value in edit { if $0.conditions.indices.contains(index) { $0.conditions[index] = value } } }))
                                        .textFieldStyle(.roundedBorder)
                                    Button { mutate { $0.conditions.remove(at: index) } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.plain).help("Remove condition")
                                }.transition(.opacity)
                            }
                            Menu {
                                ForEach(["Name contains ", "Extension is one of ", "Kind is Image", "Size greater than 1 MiB", "Modified date older than 7 days", "Tags contain Work", "Color label is Blue", "Text contains "], id: \.self) { value in
                                    Button(value) { mutate { $0.conditions.append(value) } }
                                }
                            } label: { Label("Add Condition", systemImage: "plus") }
                            .fixedSize()
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Then do these actions").font(.headline)
                            ForEach(Array(draft.actions.enumerated()), id: \.offset) { index, action in
                                HStack(alignment: .center, spacing: 10) {
                                    Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                                    TextField("Action", text: Binding(get: { model.draft?.actions[safe: index] ?? "" }, set: { value in edit { if $0.actions.indices.contains(index) { $0.actions[index] = value } } }))
                                        .textFieldStyle(.roundedBorder)
                                    Button { mutate { $0.actions.remove(at: index) } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.plain).help("Remove action")
                                }.transition(.opacity)
                            }
                            Menu {
                                ForEach(["Move to ", "Copy to ", "Rename using {stem}", "Add tag ", "Compress as ZIP", "Uncompress ZIP", "Move to Trash", "Permanently delete (requires approval)", "Run restricted script (requires approval)"], id: \.self) { value in
                                    Button(value) { mutate { $0.actions.append(value) } }
                                }
                            } label: { Label("Add Action", systemImage: "plus") }.fixedSize()
                        }
                        Label("This storyboard uses sample text. Typed rule validation and real file actions are not connected yet.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(20)
                }
                Divider()
                HStack {
                    if model.savedFeedback { Label("Saved to demo", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Discard") { model.discardDraft() }.disabled(!model.dirty)
                    Button("Test Draft…") { model.presentPreview(source: .draft) }.disabled(!model.validDraft)
                    Button("Save Demo Rule") { model.saveDraft() }.buttonStyle(.borderedProminent).disabled(!model.validDraft || !model.dirty)
                }.padding(16)
            }
        } else {
            ContentUnavailableView("Select a rule", systemImage: "slider.horizontal.3", description: Text("Create or select a demo rule to explore its conditions and actions."))
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

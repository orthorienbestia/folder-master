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
            if model.quitPending && (model.folderPending || model.liveRules.pending || model.enginePending || model.workspaceConnecting) {
                HStack { ProgressView().controlSize(.small); Text("Finishing configuration update before quitting…") }
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
                        .help(model.canPreviewDemo ? "Preview synthetic files; no folders are read" : "Choose an available sample folder first")
                        .disabled(!model.canPreviewDemo)
                    Button { model.presentPreview() } label: { Label("Simulate Run", systemImage: "play") }
                        .disabled(!model.canPreviewDemo)
                }
            }
        }
        .sheet(isPresented: $model.showPreview, onDismiss: model.previewDidDismiss) { PreviewView(model: model) }
        .confirmationDialog("Save changes to this demo rule?", isPresented: $model.showUnsaved, titleVisibility: .visible) {
            Button("Save") { model.resolveUnsaved(save: true) }.disabled(!model.validDraft)
            Button("Discard Changes", role: .destructive) { model.resolveUnsaved(save: false) }
            Button("Keep Editing", role: .cancel) { model.keepEditingDemo() }
        } message: { Text("Changes are stored in this demo session only. Your files are never changed.") }
        .animation(animation, value: model.destination)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.destination }, set: { model.selectDemoDestination($0) })) {
                Section("Watched folders") {
                    if model.folders.isEmpty { Text("No folders yet").foregroundStyle(.secondary) }
                    ForEach(model.folders) { folder in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(folder.name, systemImage: folder.symbol)
                            Text(model.demoReconnectID == folder.id ? "Reconnecting sample…" : folder.detail)
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(WorkspaceDestination.folder(folder.id))
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
            Button("Leave Demo") { model.leaveDemo() }
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
            Button("Select a Sample Folder") {
                if let first = model.folders.first { model.selectDemoDestination(.folder(first.id)) }
            }
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
        VStack(spacing: 0) {
            if let folder = model.selectedDemoFolder {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(folder.name).font(.title2.weight(.semibold))
                        Text("/Sample/\(folder.name) · in-memory folder state").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("On in sample", isOn: Binding(get: { folder.enabled }, set: model.setDemoFolderEnabled))
                        .toggleStyle(.switch).controlSize(.small)
                        .disabled(folder.availability != .available || model.demoReconnectID == folder.id)
                        .help("Session-only status; no folder is watched or processed")
                }.padding(20)
                Divider()
                if folder.availability == .unavailable {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Sample folder unavailable").font(.title2.weight(.semibold))
                        Text("This demonstrates a disconnected or inaccessible folder. Real reconnection and permission handling are not connected yet.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                        if model.demoReconnectID == folder.id {
                            ProgressView("Reconnecting sample…")
                            Text("The sample folder will stay Off.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Simulate Reconnect") { model.reconnectDemoFolder() }
                                .buttonStyle(.borderedProminent).disabled(model.demoReconnectID != nil)
                        }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.experience.rules.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView("No rules for \(folder.name) yet", systemImage: "slider.horizontal.3", description: Text("Create a disabled sample rule first. Existing files are never processed by this interface."))
                        Button("New Sample Rule") { model.addRule() }.buttonStyle(.borderedProminent)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { ruleColumns }
            }
        }
    }

    private var ruleColumns: some View {
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
                                Text("\(rule.conditions.predicateCount) conditions · \(rule.actions.count) actions").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 7).tag(rule.id)
                        .contextMenu { Button("Duplicate as Disabled") { model.experience.duplicateRule(rule.id) }.disabled(model.dirty) }
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
    @FocusState private var nameFocused: Bool
    private func edit(_ change: (inout DemoRule) -> Void) {
        guard var draft = model.draft else { return }
        change(&draft); model.draft = draft; model.savedFeedback = false
    }
    var body: some View {
        if let draft = model.draft {
            let editingSession = model.draftSessionID
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
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name").font(.subheadline.weight(.medium))
                                TextField("Rule name", text: Binding(get: { model.draft?.name ?? "" }, set: { value in edit { $0.name = value } }))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($nameFocused)
                                    .accessibilityLabel("Sample rule name")
                                if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.count > 200 {
                                    Label("Enter a name of 1–200 characters before saving.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
                                }
                            }.id("rule-editor-top")
                            ConditionTreeEditor(root: Binding(get: {
                                guard let current = model.draft, current.id == draft.id else { return draft.conditions }
                                return current.conditions
                            }, set: { root in
                                guard model.draft?.id == draft.id else { return }
                                edit { $0.conditions = root }
                            }))
                            Divider()
                            ActionChainEditor(chain: Binding(get: {
                                guard let current = model.draft, current.id == draft.id, model.draftSessionID == editingSession else { return draft.actions }
                                return current.actions
                            }, set: { chain in
                                model.updateActionDraft(chain, ruleID: draft.id, sessionID: editingSession)
                            }), conditions: draft.conditions, ruleEnabled: draft.enabled)
                            Label("Structural draft checks only. Matching, Rust regex/glob validation and file actions are not connected yet.", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(20)
                    }
                    .onChange(of: draft.id, initial: true) { _, _ in
                        scroll.scrollTo("rule-editor-top", anchor: .top)
                        nameFocused = model.draftIsNew
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if !model.validDraft {
                        Label("Correct the marked fields before saving this sample rule.", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        if model.savedFeedback { Label("Saved to demo", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Discard") { model.discardDraft() }.disabled(!model.dirty)
                        Button("Test Draft…") { model.presentPreview(source: .draft) }.disabled(!model.validDraft)
                        Button("Save Demo Rule") { model.saveDraft() }.buttonStyle(.borderedProminent).disabled(!model.validDraft || !model.dirty)
                    }
                }.padding(16)
            }
        } else {
            ContentUnavailableView("Select a rule", systemImage: "slider.horizontal.3", description: Text("Create or select a demo rule to explore its conditions and actions."))
        }
    }
}

import SwiftUI

struct PersistentWorkspaceView: View {
    @ObservedObject var model: AppModel
    @AppStorage("motionChoice") private var motion = MotionChoice.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @State private var section = "Rules"
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { model.selectedLiveFolderID }, set: { model.selectLiveFolder($0) })) {
                    Section("Your folders") {
                        ForEach(model.storedFolders) { folder in
                            Label(folder.display_name, systemImage: "folder").tag(folder.id)
                                .help(folder.fileURL?.path ?? "Folder unavailable")
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Button { model.chooseFolder() } label: { Label("Add Folder…", systemImage: "folder.badge.plus") }
                        .disabled(!model.workspaceReady || model.folderPending)
                    Button("Explore Sample Interface") { model.exploreDemo() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    SettingsLink { Label("Settings", systemImage: "gearshape") }.buttonStyle(.plain)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Label("Folder setup is live", systemImage: "internaldrive")
                    Text("Watching and file actions are not enabled in this development build.").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.font(.caption).padding(12).background(.tint.opacity(0.07))
                if let error = model.error {
                    HStack(alignment: .top) {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Spacer()
                        if !model.workspaceReady { Button("Retry") { Task { await model.retryStorage() } } }
                        Button("Dismiss") { model.error = nil }
                }.font(.callout).padding(16).background(.yellow.opacity(0.10))
                }
                if model.liveDraft != nil {
                    VStack(spacing: 0) {
                        HStack {
                            Text(model.liveDraft?.display_name ?? "Folder").font(.headline)
                            Spacer()
                            Picker("Folder view", selection: $section) { Text("Rules").tag("Rules"); Text("Folder Settings").tag("Settings") }
                                .pickerStyle(.segmented).frame(width: 260)
                        }.padding(16)
                        Divider()
                        if section == "Rules" { LiveRulesView(model: model.liveRules).disabled(model.folderPending) }
                        else { LiveFolderEditor(model: model) }
                    }
                }
                else {
                    VStack(spacing: 18) {
                        Image(systemName: "folder.badge.gearshape").font(.system(size: 48, weight: .light)).foregroundStyle(.tint)
                        Text(model.storedFolders.isEmpty ? "Start with a folder." : "Choose a folder to manage.").font(.largeTitle.weight(.semibold))
                        Text("Folder settings are saved locally and survive a restart.\nYou control the scope before any automation is enabled.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Add Folder…") { model.chooseFolder() }.buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(!model.workspaceReady || model.folderPending)
                        if model.workspaceConnecting { ProgressView("Opening local workspace…") }
                        else if !model.workspaceReady {
                            Button("Retry Local Storage") { Task { await model.retryStorage() } }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
                }
                Divider()
                HStack {
                    Label(model.engineStatus, systemImage: "internaldrive").lineLimit(1)
                    Spacer()
                    Text("\(model.storedFolders.count) saved folders · automation unavailable").foregroundStyle(.secondary)
                }.font(.caption).padding(12)
            }
        }
        .toolbar {
            ToolbarItem { Button { model.chooseFolder() } label: { Label("Add Folder", systemImage: "folder.badge.plus") }.disabled(!model.workspaceReady || model.folderPending) }
        }
        .sheet(isPresented: $model.showAddFolder) {
            if let candidate = model.folderCandidate { AddFolderSheet(model: model, candidate: candidate) }
        }
        .confirmationDialog("Save workspace changes?", isPresented: $model.showLiveUnsaved, titleVisibility: .visible) {
            Button("Save") { Task { await model.resolveLiveUnsaved(save: true) } }.disabled(!model.validWorkspaceDrafts)
            Button("Discard Changes", role: .destructive) { Task { await model.resolveLiveUnsaved(save: false) } }
            Button("Keep Editing", role: .cancel) { }
        } message: { Text("Your edited rule and folder settings are saved locally. Saving never runs files.") }
        .animation(animation, value: model.selectedLiveFolderID)
    }
    private var animation: Animation? {
        let duration = (MotionChoice(rawValue: motion) ?? .system).duration(systemReduced: systemReduced, normal: 0.12)
        return duration == 0 ? nil : .easeOut(duration: duration)
    }
}

private struct AddFolderSheet: View {
    @ObservedObject var model: AppModel
    let candidate: FolderCandidate
    @State private var name: String
    init(model: AppModel, candidate: FolderCandidate) { self.model = model; self.candidate = candidate; _name = State(initialValue: candidate.name) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add this folder").font(.title2.weight(.semibold))
            Text((try? NativeFolderAccess.url(for: candidate.path).path) ?? candidate.name)
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("Display name", text: $name).textFieldStyle(.roundedBorder)
            Label("Starts disabled. Existing files stay untouched.", systemImage: "pause.circle").font(.callout)
            Text("Other sync software may upload files in this folder independently. Folder Master does not request cloud downloads or upload your documents.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red) }
            HStack {
                if model.folderPending { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { model.showAddFolder = false; model.folderCandidate = nil }.disabled(model.folderPending)
                Button("Add Folder") { Task { _ = await model.addLiveFolder(name: name) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 200 || model.folderPending)
            }
        }.padding(24).frame(width: 480).interactiveDismissDisabled(model.folderPending)
    }
}

private struct LiveFolderEditor: View {
    @ObservedObject var model: AppModel
    @State private var showRemove = false
    private func edit(_ body: (inout StoredFolder) -> Void) {
        guard var draft = model.liveDraft else { return }
        body(&draft); model.liveDraft = draft; model.folderSavedFeedback = false
    }
    var body: some View {
        if let folder = model.liveDraft {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(folder.display_name).font(.title2.weight(.semibold))
                        Text(folder.fileURL?.path ?? "Folder address unavailable").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Label("Disabled", systemImage: "pause.circle").font(.callout).foregroundStyle(.secondary)
                }.padding(24)
                Divider()
                Form {
                    Section("Folder") {
                        TextField("Display name", text: Binding(get: { model.liveDraft?.display_name ?? "" }, set: { value in edit { $0.display_name = value } }))
                        if !model.validLiveDraft { Text("Enter a display name of 1–200 characters.").font(.caption).foregroundStyle(.red) }
                        LabeledContent("Automation", value: "Unavailable in this build")
                    }
                    Section("Scope for future automation") {
                        Toggle("Include subfolders", isOn: Binding(get: { model.liveDraft?.recursive ?? false }, set: { value in edit { $0.recursive = value } }))
                        Toggle("Include hidden files", isOn: Binding(get: { model.liveDraft?.include_hidden ?? false }, set: { value in edit { $0.include_hidden = value } }))
                        Picker("Watch mode", selection: Binding(get: { model.liveDraft?.watch_mode ?? "automatic" }, set: { value in edit { $0.watch_mode = value } })) {
                            Text("Automatic").tag("automatic"); Text("Polling").tag("polling")
                        }
                        if folder.watch_mode == "polling" {
                            Stepper("Polling interval: \(folder.poll_interval_seconds) seconds", value: Binding(get: { model.liveDraft?.poll_interval_seconds ?? 30 }, set: { value in edit { $0.poll_interval_seconds = value } }), in: 5...3600)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Exclusions · one relative pattern per line")
                            TextEditor(text: Binding(get: { model.liveDraft?.exclusions.joined(separator: "\n") ?? "" }, set: { value in edit { $0.exclusions = value.components(separatedBy: .newlines).filter { !$0.isEmpty } } }))
                                .font(.system(.body, design: .monospaced)).frame(minHeight: 95)
                            Text("Saved as setup only. Pattern matching and validation are connected with the watcher milestone.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Label("Rules can be saved in the Rules tab. Previews, watching and file actions are still being connected. Saving never runs existing files.", systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Remove Folder Configuration…", role: .destructive) { showRemove = true }
                    }
                }.formStyle(.grouped).disabled(model.folderPending)
                Divider()
                HStack {
                    if model.folderSavedFeedback { Label("Saved locally", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
                    if model.folderPending { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Discard") { model.discardLiveDraft() }.disabled(!model.liveDirty || model.folderPending)
                    Button("Save Changes") { Task { _ = await model.saveLiveFolder() } }.buttonStyle(.borderedProminent)
                        .disabled(!model.liveDirty || !model.validLiveDraft || model.folderPending)
                }.padding(16)
            }
            .confirmationDialog("Remove this folder configuration?", isPresented: $showRemove, titleVisibility: .visible) {
                Button("Remove Configuration", role: .destructive) {
                    if let saved = model.storedFolders.first(where: { $0.id == folder.id }) { Task { await model.removeLiveFolder(saved) } }
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Folder settings and current rule configurations are removed, including unsaved edits. Historical revisions remain local. The folder and its files remain untouched.") }
        }
    }
}

import SwiftUI

struct PreviewView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var inspected: UUID?
    @AppStorage("motionChoice") private var motion = MotionChoice.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("See what would change").font(.title2.weight(.semibold))
                    Text("Downloads · File invoices · Synthetic preview").foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close preview")
                    .disabled(model.previewPhase == .running)
            }.padding(24)
            HStack(spacing: 18) {
                Label("2 ready", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                Label("1 unknown", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                Label("1 needs review", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                Spacer()
                Text("No files will be read or changed").font(.caption).foregroundStyle(.secondary)
            }.font(.callout).padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            if model.previewPhase == .review {
                List(selection: $inspected) {
                    ForEach(model.experience.rows) { row in
                        HStack(spacing: 12) {
                            Toggle("Select \(row.name)", isOn: Binding(get: { model.experience.selected.contains(row.id) }, set: { value in
                                if value && row.readiness == .ready { model.experience.selected.insert(row.id) }
                                else { model.experience.selected.remove(row.id) }
                            })).labelsHidden().toggleStyle(.checkbox).disabled(row.readiness != .ready)
                            Image(systemName: "doc.richtext").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.name).fontWeight(.medium)
                                Text(row.readiness == .ready ? "Rename → Tag Finance → Move to \(row.destination)" : row.explanation)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.readiness == .ready ? "Ready" : row.readiness == .unknown ? "Unknown" : "Needs review")
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }.padding(.vertical, 10).tag(row.id)
                    }
                }
                if let row = model.experience.rows.first(where: { $0.id == inspected }) {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Why this result?", systemImage: "text.magnifyingglass").font(.headline)
                        Text(row.explanation).font(.callout).foregroundStyle(.secondary)
                        if row.readiness == .ready { Text("Supported undo would be checked against unchanged output and original-path availability.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(20)
                }
            } else {
                simulationResult
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            Divider()
            HStack {
                if model.previewPhase == .review {
                    Button("Select Ready") { model.experience.selectReady() }
                    Button("Select None") { model.experience.selected.removeAll() }
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Simulate \(model.experience.executableSelection.count) Files") { model.simulateRun() }
                        .buttonStyle(.borderedProminent).disabled(model.experience.executableSelection.isEmpty)
                } else if model.previewPhase == .running {
                    Text("Simulation only · your files are untouched").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel Simulation") { model.cancelSimulation() }
                } else {
                    Text("No filesystem actions were executed.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("View Demo History") { model.destination = .history; dismiss() }
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
            }.padding(20)
        }
        .frame(width: 760, height: 560)
        .interactiveDismissDisabled(model.previewPhase == .running)
        .animation(animation, value: model.previewPhase)
    }
    private var animation: Animation? {
        let duration = (MotionChoice(rawValue: motion) ?? .system).duration(systemReduced: systemReduced, normal: 0.22)
        return duration == 0 ? nil : .easeOut(duration: duration)
    }
    private var simulationResult: some View {
        VStack(spacing: 16) {
            if model.previewPhase == .running {
                ProgressView(value: Double(model.completedCount), total: Double(max(1, model.experience.executableSelection.count))).frame(width: 240)
                Text("Simulating the planned flow…").font(.title3.weight(.medium))
                Text("\(model.completedCount) of \(model.experience.executableSelection.count) sample files").foregroundStyle(.secondary)
            } else {
                Image(systemName: model.previewPhase == .finished ? "checkmark.circle" : "pause.circle")
                    .font(.system(size: 42, weight: .light)).foregroundStyle(.tint)
                Text(model.previewPhase == .finished ? "Simulation complete" : "Simulation canceled").font(.title2.weight(.semibold))
                Text("\(model.completedCount) sample results added to demo history.").foregroundStyle(.secondary)
            }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var selected: UUID?
    @State private var showUndoExplanation = false
    private var filtered: [DemoActivity] { model.activities.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History").font(.title2.weight(.semibold))
                    Text("A clear record of every change.").foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search activity", text: $query).textFieldStyle(.roundedBorder).frame(width: 220)
            }.padding(24)
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No activity yet" : "No matching activity", systemImage: "clock.arrow.circlepath", description: Text(query.isEmpty ? "Run a sample preview to explore the history flow. Real operation history is not connected yet." : "Try a different filename."))
            } else {
                List(selection: $selected) {
                    ForEach(filtered) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "testtube.2").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).fontWeight(.medium)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.time, style: .time).font(.caption).foregroundStyle(.secondary)
                            Button("Undo Details") { showUndoExplanation = true }.controlSize(.small)
                        }.padding(.vertical, 10).tag(item.id)
                    }
                }
            }
        }
        .alert("Undo requires a real operation", isPresented: $showUndoExplanation) {
            Button("Understood", role: .cancel) { }
        } message: { Text("These entries are synthetic. Supported undo will validate unchanged file identities, contents, original paths and dependencies before restoring files. No fake Undo operation is performed here.") }
    }
}

struct AppSettingsView: View {
    @AppStorage("motionChoice") private var choice = MotionChoice.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    var body: some View {
        Form {
            Section("Appearance & motion") {
                Picker("Animations", selection: $choice) {
                    ForEach(MotionChoice.allCases) { option in Text(option.rawValue).tag(option.rawValue) }
                }
                Text(systemReduced ? "System Reduce Motion is enabled and takes priority." : "Motion follows your choice and macOS accessibility preferences.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Appearance", value: "Follow System")
            }
            Section("Development foundation") {
                Label("Rust engine · native SwiftUI interface", systemImage: "cpu")
                Text("Interactive previews use synthetic data. Folder monitoring, OCR, file actions, history storage and undo are still being implemented.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(8)
    }
}

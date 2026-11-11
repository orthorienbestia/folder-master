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
                    Text(model.previewSource == .draft ? "Test Draft" : "See what would change").font(.title2.weight(.semibold))
                    Text("\(model.previewRuleName) · Synthetic invoice plan").foregroundStyle(.secondary)
                    Text("Fixed storyboard examples; your rule is not evaluated and no files are read.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close preview").accessibilityLabel("Close preview")
                    .disabled(model.previewPhase.isActive)
            }.padding(24)
            HStack(spacing: 16) {
                Label("\(count(.ready)) ready", systemImage: "checkmark.circle")
                Label("\(count(.unknown)) unknown", systemImage: "questionmark.circle")
                Label("\(count(.conflict)) needs review", systemImage: "exclamationmark.circle")
                Spacer()
            }.font(.callout).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            if model.previewPhase == .review { review }
            else { result.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity) }
            Divider()
            footer.padding(20)
        }
        .frame(width: 760, height: 600)
        .interactiveDismissDisabled(model.previewPhase.isActive)
        .animation(animation, value: model.previewPhase)
        .confirmationDialog("Simulate \(model.confirmationCount) selected file chains?", isPresented: $model.showRunConfirmation, titleVisibility: .visible) {
            Button("Simulate Selected Chains") { model.simulateRun() }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { model.cancelRunConfirmation() }
        } message: {
            Text("Each selected sample file includes its whole rename → tag → move chain. Outcome: \(model.runScenario.rawValue). This changes session-only sample history, never your files or automation pause setting.")
        }
        .onDisappear { model.cancelRunConfirmation() }
    }

    private func count(_ readiness: PreviewReadiness) -> Int { model.experience.rows.filter { $0.readiness == readiness }.count }
    private var review: some View {
        VStack(spacing: 0) {
            List(selection: $inspected) {
                ForEach(model.experience.rows) { row in
                    HStack(spacing: 12) {
                        if model.previewSource == .savedRule {
                            Toggle("Select whole chain for \(row.name)", isOn: Binding(get: { model.experience.selected.contains(row.id) }, set: { value in
                                if value && row.readiness == .ready { model.experience.selected.insert(row.id) }
                                else { model.experience.selected.remove(row.id) }
                            })).labelsHidden().toggleStyle(.checkbox).disabled(row.readiness != .ready)
                        }
                        Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.name).fontWeight(.medium)
                            Text(row.readiness == .ready ? "Rename → Tag Finance → Move to \(row.destination)" : row.explanation)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.readiness == .ready ? "Ready" : row.readiness == .unknown ? "Unknown" : "Needs review")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }.padding(.vertical, 8).tag(row.id)
                }
            }
            if let row = model.experience.rows.first(where: { $0.id == inspected }) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Why this result?", systemImage: "text.magnifyingglass").font(.headline)
                    Text(row.explanation).font(.callout).foregroundStyle(.secondary)
                    if row.readiness == .ready {
                        Text("Before: /Sample/Downloads/\(row.name)")
                        Text("After: /Sample/\(row.destination)2026-11-11-\(row.name)")
                        Text("Undo would require unchanged outputs, available original paths and valid dependencies.").foregroundStyle(.secondary)
                    }
                }.font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            if model.previewSource == .savedRule {
                Divider()
                Picker("Sample outcome", selection: $model.runScenario) {
                    ForEach(DemoRunScenario.allCases) { scenario in Text(scenario.rawValue).tag(scenario) }
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if model.previewPhase == .review {
            HStack {
                if model.previewSource == .draft {
                    Label("Test Draft has no Apply action", systemImage: "eye").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                } else {
                    Button("Select Ready") { model.experience.selectReady() }
                    Button("Select None") { model.experience.selected.removeAll() }
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Review \(model.experience.executableSelection.count) Selected…") { model.requestSimulation() }
                        .buttonStyle(.borderedProminent).disabled(model.experience.executableSelection.isEmpty)
                }
            }
        } else if model.previewPhase.isActive {
            HStack {
                Text("Simulation only · no real file effects").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.previewPhase == .paused { Button("Resume Simulation") { model.resumeSimulation() } }
                else { Button(model.previewPhase == .pausing ? "Pausing…" : "Pause Simulation") { model.pauseSimulation() }.disabled(model.previewPhase == .pausing) }
                Button("Cancel Simulation") { model.cancelSimulation() }.keyboardShortcut(.cancelAction)
            }
        } else {
            HStack {
                Text("Completed sample steps are retained in history.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("View Demo History") { model.destination = .history; dismiss() }
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var result: some View {
        VStack(spacing: 16) {
            if model.previewPhase.isActive {
                ProgressView(value: Double(model.processedCount), total: Double(max(1, model.runTotal))).frame(width: 260)
                Text(model.previewPhase == .pausing ? "Finishing the current sample file…" : model.previewPhase == .paused ? "Simulation paused at a boundary" : "Simulating the confirmed plan…")
                    .font(.title3.weight(.medium))
                Text("\(model.processedCount) of \(model.runTotal) sample file chains recorded").foregroundStyle(.secondary)
                if model.previewPhase == .pausing { Text("No next file starts after this sample boundary.").font(.caption).foregroundStyle(.secondary) }
            } else {
                Image(systemName: model.previewPhase == .finished ? "checkmark.circle" : model.previewPhase == .canceled ? "pause.circle" : "exclamationmark.triangle")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                Text(resultTitle).font(.title2.weight(.semibold))
                Text("\(model.completedCount) completed · \(model.partialCount) partial · \(model.failedCount) failed").foregroundStyle(.secondary)
                Text("\(model.runTotal - model.processedCount) not started. No real files were read or changed.").font(.callout).foregroundStyle(.secondary)
                if model.partialCount > 0 { Text("A sample rename and tag remain after the move failure. Inspect its steps in history.").font(.callout).multilineTextAlignment(.center).frame(maxWidth: 460) }
            }
        }.padding(24).accessibilityElement(children: .contain)
    }
    private var resultTitle: String {
        switch model.previewPhase {
        case .finished: return "Simulation complete"
        case .partial: return "Simulation partially completed"
        case .failed: return "Simulation failed before changing files"
        default: return "Simulation canceled"
        }
    }
    private var animation: Animation? {
        guard model.previewPhase != .partial, model.previewPhase != .failed, model.previewPhase != .canceled,
              model.previewPhase != .pausing, model.previewPhase != .paused else { return nil }
        let duration = (MotionChoice(rawValue: motion) ?? .system).duration(systemReduced: systemReduced, normal: 0.22)
        return duration == 0 ? nil : .easeOut(duration: duration)
    }
}

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
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
                Text("Folder configuration and pause settings are saved locally. Sample rule previews use synthetic data. Watching, OCR, file actions, history execution and undo are still being implemented.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(8).disabled(!model.workspaceReady || model.quitPending)
    }
}

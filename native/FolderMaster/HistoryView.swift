import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var selected: UUID?
    @State private var attentionOnly = false
    private var filtered: [DemoActivity] {
        model.activities.filter {
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) &&
            (!attentionOnly || $0.outcome == .partial || $0.outcome == .failed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History").font(.title2.weight(.semibold))
                    Text("Session-only sample activity · no file effects").foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search activity", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            }.padding(24)
            Toggle("Needs attention only", isOn: $attentionOnly).toggleStyle(.checkbox).padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView(model.activities.isEmpty ? "No activity yet" : "No matching activity", systemImage: "clock.arrow.circlepath", description: Text(model.activities.isEmpty ? "Preview a saved sample rule, then simulate a confirmed plan to explore results and undo." : "Change your search or turn off the attention filter."))
            } else {
                HSplitView {
                    List(selection: $selected) {
                        ForEach(filtered) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.outcome == .partial || item.outcome == .failed ? "exclamationmark.triangle" : "testtube.2").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).fontWeight(.medium).lineLimit(1).help(item.name)
                                    Text(item.undone ? "Completed · undo recorded" : item.outcome.rawValue).font(.caption)
                                    Text(item.time, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8).tag(item.id)
                        }
                    }.frame(minWidth: 210)
                    if let item = filtered.first(where: { $0.id == selected }) {
                        inspector(item).frame(minWidth: 260, idealWidth: 320, maxWidth: 360, maxHeight: .infinity, alignment: .top)
                    } else {
                        ContentUnavailableView("Select a result", systemImage: "doc.text.magnifyingglass", description: Text("Inspect actual sample steps and why an inverse is available or blocked."))
                            .frame(minWidth: 260, idealWidth: 320)
                    }
                }
            }
        }
        .sheet(item: $model.undoCandidate) { item in DemoUndoPreview(model: model, item: item) }
    }

    private func inspector(_ item: DemoActivity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.outcome.rawValue).font(.headline)
                Text(item.detail).font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("Recorded sample steps").font(.subheadline.weight(.medium))
                ForEach(item.steps, id: \.self) { step in Text(step).font(.callout) }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before: \(item.beforePath)")
                    Text("After: \(item.afterPath)")
                }.font(.caption.monospaced()).textSelection(.enabled)
                if let reason = model.undoBlockReason(item.id) {
                    Label(reason, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("A real inverse would first validate unchanged outputs, original-path availability and dependencies.").font(.callout).foregroundStyle(.secondary)
                }
                Button("Preview Sample Undo…") { model.undoCandidate = item }
                if let originalID = item.originalActivityID {
                    Button("Inspect Original Record") { selected = originalID }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DemoUndoPreview: View {
    @ObservedObject var model: AppModel
    let item: DemoActivity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview Sample Undo").font(.title2.weight(.semibold))
            Text(item.name).font(.headline)
            Text("Synthetic inverse only. No filesystem checks or changes will run.").font(.callout).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let reason = model.undoBlockReason(item.id) {
                        Label("Undo unavailable", systemImage: "exclamationmark.triangle").font(.headline)
                        Text(reason)
                    } else {
                        Text("Reverse dependency order").font(.headline)
                        Text("1. Move the unchanged sample output back to its original folder.")
                        Text("2. Restore the affected tag values.")
                        Text("3. Restore the original filename.")
                        Text("From: \(item.afterPath)").font(.caption.monospaced())
                        Text("To: \(item.beforePath)").font(.caption.monospaced())
                        Text("The original record stays in history; a separate undo record is appended.").foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Simulate Undo") { model.simulateUndo() }
                    .buttonStyle(.borderedProminent).disabled(model.undoBlockReason(item.id) != nil)
            }
        }.padding(24).frame(width: 540, height: 450)
    }
}

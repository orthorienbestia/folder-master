import SwiftUI

@main
struct FolderMasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Folder Master", id: "main") {
            WorkspaceView(model: model)
                .frame(minWidth: 820, minHeight: 560)
                .task { delegate.model = model; await model.connect() }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Demo Rule") { model.addRule() }
                    .keyboardShortcut("n")
                    .disabled(!model.demo || model.selectedDemoFolder?.availability != .available)
            }
        }
        MenuBarExtra("Folder Master", systemImage: "tray.2") {
            StatusMenu(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings { AppSettingsView(model: model).frame(width: 480, height: 320) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminating = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            if let model, !(await model.prepareForQuit(confirm: { self.confirmFolderChanges(model) })) {
                terminating = false
                NSApp.reply(toApplicationShouldTerminate: false)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
                return
            }
            await model?.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    private func confirmFolderChanges(_ model: AppModel) -> QuitDecision {
        let alert = NSAlert()
        alert.messageText = "Save folder changes before quitting?"
        alert.informativeText = "Save keeps your folder settings. Discard Changes leaves the saved settings unchanged."
        alert.addButton(withTitle: "Save").isEnabled = model.validLiveDraft
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}

struct StatusMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Folder Master · Development")
        Text(model.engineStatus)
        Divider()
        Button("Open Folder Master…") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.disabled(model.quitPending)
        Button(model.enginePaused ? "Resume engine (development)" : "Pause engine (development)") {
            model.setPaused(!model.enginePaused)
        }
        .disabled(model.enginePending || !model.workspaceReady || model.quitPending)
        Text("File automation is not enabled in this build")
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Folder Master") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

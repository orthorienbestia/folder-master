import Foundation

enum MotionChoice: String, CaseIterable, Identifiable {
    case system = "Follow System", reduced = "Reduced", off = "Off"
    var id: String { rawValue }
    func duration(systemReduced: Bool, normal: Double) -> Double {
        if self == .off { return 0 }
        if self == .reduced || systemReduced { return min(normal, 0.1) }
        return min(normal, 0.3)
    }
    func allowsMovement(systemReduced: Bool) -> Bool { self == .system && !systemReduced }
}

struct DemoRule: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var enabled = false
    var conditions: [String] = []
    var actions: [String] = []
}

enum PreviewReadiness: String { case ready, unknown, conflict }
struct DemoPreviewRow: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var readiness: PreviewReadiness
    var destination = "Receipts/2026/"
    var explanation: String {
        switch readiness {
        case .ready: return "PDF extension and invoice text match. Would rename, tag, then move."
        case .unknown: return "Text could not be fully extracted. This file cannot be selected."
        case .conflict: return "Destination needs review. Refresh after resolving the conflict."
        }
    }
}

struct ExperienceState {
    var rules: [DemoRule] = []
    var rows: [DemoPreviewRow] = []
    var selected = Set<UUID>()
    mutating func selectReady() { selected = Set(rows.filter { $0.readiness == .ready }.map(\.id)) }
    var executableSelection: [DemoPreviewRow] { rows.filter { selected.contains($0.id) && $0.readiness == .ready } }
    mutating func duplicateRule(_ id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        var copy = rules[index]
        copy.id = UUID()
        copy.name += " Copy"
        copy.enabled = false
        rules.insert(copy, at: index + 1)
    }
}

struct DemoFolder: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var detail: String
}

enum DemoSamples {
    static let folders = [
        DemoFolder(name: "Downloads", symbol: "arrow.down.circle", detail: "Sample folder · local only"),
        DemoFolder(name: "Scans", symbol: "doc.viewfinder", detail: "Sample folder · paused"),
        DemoFolder(name: "Projects", symbol: "folder", detail: "Sample folder · no rules"),
    ]
    static let rules = [
        DemoRule(name: "File invoices", enabled: true, conditions: ["Extension is one of pdf", "Text contains invoice"], actions: ["Rename using {created:yyyy-MM-dd}-{stem}", "Add tag Finance", "Move to Receipts/2026"]),
        DemoRule(name: "Keep screenshots together", enabled: true, conditions: ["Name begins with Screenshot", "Kind is Image"], actions: ["Move to Pictures/Screenshots"]),
        DemoRule(name: "Review old installers", conditions: ["Extension is one of dmg, pkg", "Modified date older than 30 days"], actions: ["Move to Review/Installers"]),
    ]
    static var preview: [DemoPreviewRow] { [
        DemoPreviewRow(name: "invoice-november.pdf", readiness: .ready),
        DemoPreviewRow(name: "invoice-studio.pdf", readiness: .ready),
        DemoPreviewRow(name: "scan-locked.pdf", readiness: .unknown),
        DemoPreviewRow(name: "invoice-copy.pdf", readiness: .conflict),
    ] }
}

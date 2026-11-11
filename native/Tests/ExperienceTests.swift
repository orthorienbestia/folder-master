import XCTest

final class ExperienceTests: XCTestCase {
    func testSystemReductionAlwaysWinsOverDefaultMotion() {
        XCTAssertFalse(MotionChoice.system.allowsMovement(systemReduced: true))
        XCTAssertLessThanOrEqual(MotionChoice.system.duration(systemReduced: true, normal: 0.22), 0.1)
        XCTAssertFalse(MotionChoice.reduced.allowsMovement(systemReduced: false))
        XCTAssertEqual(MotionChoice.off.duration(systemReduced: false, normal: 0.22), 0)
        XCTAssertEqual(MotionChoice.off.duration(systemReduced: true, normal: 0.22), 0)
    }

    func testUnreadyRowsCannotBecomeExecutableEvenWhenSelected() {
        let ready = DemoPreviewRow(name: "invoice.pdf", readiness: .ready)
        let unknown = DemoPreviewRow(name: "locked.pdf", readiness: .unknown)
        let conflict = DemoPreviewRow(name: "duplicate.pdf", readiness: .conflict)
        var state = ExperienceState(rows: [ready, unknown, conflict], selected: [ready.id, unknown.id, conflict.id])
        XCTAssertEqual(state.executableSelection.map(\.name), ["invoice.pdf"])
        state.selectReady()
        XCTAssertEqual(state.selected, [ready.id])
    }

    func testDuplicateGetsIndependentIdentityAndStartsDisabled() {
        let original = DemoRule(name: "Invoices", enabled: true, conditions: ["Extension is pdf"], actions: ["Move to Receipts"])
        var state = ExperienceState(rules: [original])
        state.duplicateRule(original.id)
        XCTAssertEqual(state.rules.count, 2)
        guard state.rules.count == 2 else { return }
        XCTAssertNotEqual(state.rules[0].id, state.rules[1].id)
        XCTAssertFalse(state.rules[1].enabled)
        XCTAssertEqual(state.rules[1].conditions, ["Extension is pdf"])
        XCTAssertEqual(state.rules[1].actions, ["Move to Receipts"])
    }
}

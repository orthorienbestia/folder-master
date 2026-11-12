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
        let original = DemoRule(name: "Invoices", enabled: true, conditions: .group(children: [.predicate(.init(field: .extensionName, text: "pdf"))]), actions: .init(steps: [DemoSamples.moveAction("Receipts")]))
        var state = ExperienceState(rules: [original])
        state.duplicateRule(original.id)
        XCTAssertEqual(state.rules.count, 2)
        guard state.rules.count == 2 else { return }
        XCTAssertNotEqual(state.rules[0].id, state.rules[1].id)
        XCTAssertFalse(state.rules[1].enabled)
        XCTAssertEqual(state.rules[1].conditions.children.first?.predicateValue?.field, .extensionName)
        XCTAssertEqual(state.rules[1].conditions.children.first?.predicateValue?.text, "pdf")
        XCTAssertTrue(state.rules[1].conditions.allIDs.isDisjoint(with: original.conditions.allIDs))
        XCTAssertEqual(state.rules[1].actions.steps[0].kind, .move)
        XCTAssertEqual(state.rules[1].actions.steps[0].destination.subfolder, "Receipts")
        XCTAssertNotEqual(state.rules[1].actions.steps[0].id, original.actions.steps[0].id)
    }
    func testDuplicateRemapsCaptureSourceToItsIndependentConditionTree() {
        let source = ConditionDraftNode.predicate(.init(operation: .regex, text: "(?P<year>[0-9]+)"))
        var rename = ActionDraft(.rename)
        rename.filenameTemplate = "{capture:year}"; rename.captureConditionID = source.id
        let original = DemoRule(name: "Captured year", enabled: true, conditions: .group(children: [source]), actions: .init(steps: [rename]))
        var state = ExperienceState(rules: [original]); state.duplicateRule(original.id)
        let copy = state.rules[1]
        XCTAssertFalse(copy.enabled)
        XCTAssertNotEqual(copy.actions.steps[0].captureConditionID, source.id)
        XCTAssertEqual(copy.actions.steps[0].captureConditionID, copy.conditions.children[0].id)
        XCTAssertTrue(copy.actions.issues(enabled: copy.enabled, conditions: copy.conditions).isEmpty)
    }

}

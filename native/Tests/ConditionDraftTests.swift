import XCTest

final class ConditionDraftTests: XCTestCase {
    func testEmptyAndOverdeepGroupsCannotBeSaved() {
        let empty = ConditionDraftNode.group()
        XCTAssertTrue(empty.validationIssues.contains { $0.code == .emptyGroup && $0.nodeID == empty.id })
        let leaf = ConditionDraftNode.predicate(.init(text: "invoice"))
        let deep = ConditionDraftNode.group(children: [.group(.any, children: [.group(.none, children: [.group(children: [leaf])])])])
        XCTAssertTrue(deep.validationIssues.contains { $0.code == .groupDepth })
        let excess = ConditionDraftNode.group(children: (0..<51).map { _ in leaf.renewedIdentity() })
        XCTAssertTrue(excess.validationIssues.contains { $0.code == .predicateLimit })
    }

    func testSizeInputConvertsExactlyWithoutFloatingPointRounding() {
        XCTAssertEqual(ConditionSizeUnit.kib.bytes(from: "0.5"), 512)
        XCTAssertNil(ConditionSizeUnit.kib.bytes(from: "0.1"))
        XCTAssertEqual(ConditionSizeUnit.gib.bytes(from: "0.000000000931322574615478515625"), 1)
        XCTAssertEqual(ConditionSizeUnit.gib.bytes(from: "17179869183.999999999068677425384521484375"), UInt64.max)
        XCTAssertEqual(ConditionSizeUnit.bytes.bytes(from: "18446744073709551615"), UInt64.max)
        for text in ["18446744073709551616", "-1", "NaN", "1.5", "", "1e3"] { XCTAssertNil(ConditionSizeUnit.bytes.bytes(from: text), text) }
    }

    func testPredicatesRejectWrongOperatorsMissingValuesAndReversedRanges() {
        let id = UUID()
        XCTAssertTrue(ConditionPredicateDraft(field: .size, operation: .regex, text: "1").issues(nodeID: id).contains { $0.code == .invalidOperator })
        XCTAssertTrue(ConditionPredicateDraft(field: .text).issues(nodeID: id).contains { $0.code == .missingValue })
        var size = ConditionPredicateDraft(field: .size, operation: .between, text: "2")
        size.upperText = "1"
        XCTAssertTrue(size.issues(nodeID: id).contains { $0.code == .reversedRange })
        var date = ConditionPredicateDraft(field: .date, operation: .dateRange)
        date.startDate = Date(timeIntervalSince1970: 2); date.endDate = Date(timeIntervalSince1970: 1)
        XCTAssertTrue(date.issues(nodeID: id).contains { $0.code == .invalidDateRange })
        XCTAssertTrue(ConditionPredicateDraft(field: .extensionName, text: "pdf,,jpg").issues(nodeID: id).contains { $0.code == .missingValue })
    }

    func testAllFieldFamiliesCanExpressValidStructuredInput() {
        var kind = ConditionPredicateDraft(field: .kind); kind.kind = .image
        var size = ConditionPredicateDraft(field: .size, operation: .between, text: "0.5"); size.upperText = "2"; size.sizeUnit = .kib
        var tags = ConditionPredicateDraft(field: .tags); tags.tagNames = ["Work", "Annual, reports"]
        var label = ConditionPredicateDraft(field: .label); label.labels = [.none, .blue]
        var text = ConditionPredicateDraft(field: .text, operation: .notContains, text: "invoice"); text.textSource = .forceOCR
        let values = [ConditionPredicateDraft(text: " "), .init(field: .extensionName, text: ".PDF, gz"), kind, size, .init(field: .date, text: "1.5"), tags, label, text]
        for value in values { XCTAssertTrue(value.issues(nodeID: UUID()).isEmpty, value.field.rawValue) }
        XCTAssertEqual(values[1].normalizedExtensions, ["pdf", "gz"])
        tags.tagEntry = "Unfinished"
        XCTAssertTrue(tags.issues(nodeID: UUID()).contains { $0.code == .pendingTag })
        XCTAssertTrue(ConditionPredicateDraft(field: .tags, operation: .empty).issues(nodeID: UUID()).isEmpty)
    }

    func testDeletingAndReorderingPreservesTheIdentityOfRemainingInputs() {
        let a = ConditionDraftNode.predicate(.init(text: "A")), b = ConditionDraftNode.predicate(.init(text: "B")), c = ConditionDraftNode.predicate(.init(text: "C"))
        var tree = ConditionDraftNode.group(children: [a,b,c])
        let saved = tree
        XCTAssertEqual(tree.focusAfterRemoving(a.id), b.id)
        XCTAssertTrue(tree.remove(a.id))
        XCTAssertTrue(tree.move(c.id, by: -1))
        XCTAssertEqual(tree.children.map(\.id), [c.id,b.id])
        XCTAssertTrue(tree.update(b.id) { $0.content = .predicate(.init(text: "Edited B")) })
        XCTAssertEqual(tree.node(b.id)?.predicateValue?.text, "Edited B")
        XCTAssertEqual(saved.node(b.id)?.predicateValue?.text, "B")
        XCTAssertFalse(tree.remove(tree.id))
        XCTAssertFalse(tree.update(a.id) { $0.content = .predicate(.init(text: "Stale")) })
    }

    func testEditingCannotExceedGroupDepthOrPredicateLimits() {
        var tree = ConditionDraftNode.group()
        let second = tree.addGroup(to: tree.id)
        XCTAssertNotNil(second)
        guard let second else { return }
        let third = tree.addGroup(to: second)
        XCTAssertNotNil(third)
        guard let third else { return }
        XCTAssertNil(tree.addGroup(to: third))
        XCTAssertEqual(tree.groupLevel(third), 3)
        while tree.predicateCount < 50 {
            guard tree.addPredicate(to: tree.id) != nil else { XCTFail("Stopped before fifty predicates"); return }
        }
        XCTAssertNil(tree.addPredicate(to: tree.id))
        XCTAssertNil(tree.addGroup(to: tree.id))
    }

    func testDuplicateTreeGetsIndependentRowIdentitiesAndKeepsValues() {
        let tree = ConditionDraftNode.group(.any, children: [.predicate(.init(text: "invoice")), .group(.none, children: [.predicate(.init(field: .extensionName, text: "tmp"))])])
        let copy = tree.renewedIdentity()
        XCTAssertTrue(tree.allIDs.isDisjoint(with: copy.allIDs))
        XCTAssertEqual(copy.children[0].predicateValue, tree.children[0].predicateValue)
        XCTAssertEqual(copy.predicateCount, tree.predicateCount)
    }
}

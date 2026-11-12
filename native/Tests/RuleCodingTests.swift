import XCTest

final class RuleCodingTests: XCTestCase {
    func testDefinitionUsesRustSchemaAndRetainsExactSizeAndIdentity() throws {
        var size = ConditionPredicateDraft(field: .size)
        size.sizeUnit = .bytes
        size.text = String(UInt64.max)
        let rule = DemoRule(
            name: "Large files", conditions: .group(children: [.predicate(size)]),
            actions: .init(steps: [ActionDraft(.rename)]))
        let definition = try StoredRuleDefinition(draft: rule)
        let value = try JSONDecoder().decode(RuleValue.self, from: JSONEncoder().encode(definition))
        XCTAssertEqual(try value["schema_version"].uint(), 1)
        XCTAssertEqual(try value["id"].uuid(), rule.id)
        let predicate = try value["conditions"]["expression"]["children"].array()[0]["expression"]["predicate"]
        XCTAssertEqual(try predicate["test"]["bytes"].uint(), UInt64.max)
        let loaded = try JSONDecoder().decode(StoredRuleDefinition.self, from: JSONEncoder().encode(definition)).draft()
        XCTAssertEqual(loaded.id, rule.id)
        XCTAssertEqual(loaded.conditions.id, rule.conditions.id)
        XCTAssertEqual(try StoredRuleDefinition(draft: loaded), definition)
        XCTAssertEqual(loaded.actions, rule.actions)
    }
    func testSampleLocationAndInvalidValuesCannotBecomeSavedConfiguration() throws {
        var action = ActionDraft(.copy)
        action.destination.root = .sample("/Sample")
        var rule = DemoRule(
            name: "Copy", conditions: .group(children: [.predicate(.init(text: "a"))]), actions: .init(steps: [action]))
        XCTAssertThrowsError(try StoredRuleDefinition(draft: rule))
        rule.actions = .init(steps: [ActionDraft(.rename)])
        rule.conditions = .group()
        XCTAssertThrowsError(try StoredRuleDefinition(draft: rule))
    }
    func testUnknownSchemaAndOptionsAreNotPresentedAsEditableValues() throws {
        for json in ["{\"schema_version\":2}", "{}"] {
            let definition = try JSONDecoder().decode(StoredRuleDefinition.self, from: Data(json.utf8))
            XCTAssertThrowsError(try definition.draft())
        }
        let rule = DemoRule(
            name: "Unknown option", conditions: .group(children: [.predicate(.init(text: "a"))]),
            actions: .init(steps: [ActionDraft(.rename)]))
        var object =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredRuleDefinition(draft: rule)))
            as! [String: Any]
        object["future_option"] = true
        let definition = try JSONDecoder().decode(
            StoredRuleDefinition.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try definition.draft())
    }
    func testValidLabelOrderAndIndependentArchiveCaptureSourcesRemainEditable() throws {
        var label = ConditionPredicateDraft(field: .label)
        label.labels = [.none, .blue]
        let labelRule = DemoRule(
            name: "Labels", conditions: .group(children: [.predicate(label)]),
            actions: .init(steps: [ActionDraft(.rename)]))
        let json = String(decoding: try JSONEncoder().encode(StoredRuleDefinition(draft: labelRule)), as: UTF8.self)
            .replacingOccurrences(of: "[\"none\",\"blue\"]", with: "[\"blue\",\"none\"]")
        let loaded = try JSONDecoder().decode(StoredRuleDefinition.self, from: Data(json.utf8)).draft()
        XCTAssertEqual(loaded.conditions.children[0].predicateValue?.labels, [.none, .blue])

        let first = ConditionDraftNode.predicate(.init(operation: .regex, text: "(?P<first>.+)"))
        let second = ConditionDraftNode.predicate(.init(operation: .regex, text: "(?P<second>.+)"))
        var action = ActionDraft(.compress)
        action.destination.root = .init(
            path: Data("/fixture".utf8), bookmark: Data("bookmark".utf8), displayPath: "/fixture")
        action.destination.subfolder = "{capture:first}"
        action.filenameTemplate = "{capture:second}.zip"
        action.captureConditionID = first.id
        action.archiveCaptureConditionID = first.id
        let rule = DemoRule(
            name: "Captures", conditions: .group(children: [first, second]), actions: .init(steps: [action]))
        var object =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredRuleDefinition(draft: rule)))
            as! [String: Any]
        var actions = object["actions"] as! [[String: Any]]
        var body = actions[0]["action"] as! [String: Any]
        var filename = body["filename"] as! [String: Any]
        filename["capture_condition_id"] = second.id.uuidString.lowercased()
        body["filename"] = filename
        actions[0]["action"] = body
        object["actions"] = actions
        let external = try JSONDecoder().decode(
            StoredRuleDefinition.self, from: JSONSerialization.data(withJSONObject: object))
        let duplicate = try external.draft()
        let value = try JSONDecoder().decode(
            RuleValue.self, from: JSONEncoder().encode(StoredRuleDefinition(draft: duplicate)))
        let result = try value["actions"].array()[0]["action"]
        XCTAssertEqual(try result["destination"]["subfolder"]["capture_condition_id"].uuid(), first.id)
        XCTAssertEqual(try result["filename"]["capture_condition_id"].uuid(), second.id)
    }
}

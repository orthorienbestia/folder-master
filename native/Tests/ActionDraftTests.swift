import XCTest

final class ActionDraftTests: XCTestCase {
    private let conditions = ConditionDraftNode.group(children: [.predicate(.init(text: "invoice"))])

    func testTerminalActionsBlockFollowingStepsAndContinue() {
        for kind in [ActionKind.trash, .delete, .uncompress, .script] {
            var chain = ActionChainDraft(steps: [], behavior: .continueRules)
            XCTAssertNotNil(chain.append(kind))
            XCTAssertEqual(chain.behavior, .stop)
            XCTAssertNil(chain.append(.rename))
            let invalid = ActionChainDraft(steps: [ActionDraft(kind), ActionDraft(.rename)], behavior: .continueRules)
            let codes = invalid.issues(enabled: false, conditions: conditions).map(\.code)
            XCTAssertTrue(codes.contains("afterTerminal"), kind.rawValue)
            XCTAssertTrue(codes.contains("terminalContinue"), kind.rawValue)
        }
    }
    func testEmptyAndOversizedChainsCannotSave() {
        XCTAssertTrue(ActionChainDraft().issues(enabled: false, conditions: conditions).contains { $0.code == "actionCount" })
        var chain = ActionChainDraft()
        for _ in 0..<20 { XCTAssertNotNil(chain.append(.rename)) }
        XCTAssertNil(chain.append(.copy))
        chain.steps.append(ActionDraft(.rename))
        XCTAssertTrue(chain.issues(enabled: false, conditions: conditions).contains { $0.code == "actionCount" })
    }
    func testDestinationAndTemplateValidationRejectsMissingRootsAndEscapes() {
        var move = ActionDraft(.move)
        XCTAssertTrue(move.issues(enabled: false, conditions: conditions).contains { $0.code == "destination" })
        move.destination.root = .sample("/Sample/Output")
        XCTAssertTrue(move.issues(enabled: false, conditions: conditions).isEmpty)
        move.destination.subfolder = "../outside"
        XCTAssertFalse(move.issues(enabled: false, conditions: conditions).isEmpty)
        for invalid in ["../file", "/file", "a/b", "", "{missing}", "{stem", "{created:yyyy/MM}", "a\0b"] {
            XCTAssertFalse(ActionTemplateDraft.issues(invalid, filename: true).isEmpty, invalid)
        }
        XCTAssertTrue(ActionTemplateDraft.issues("{created:yyyy-MM-dd}-{stem}-{counter:3}", filename: true).isEmpty)
        XCTAssertTrue(ActionTemplateDraft.issues("Receipts/{now:yyyy-MM}/{stem}", filename: false).isEmpty)
        var rename = ActionDraft(.rename); rename.renameMode = .replace
        XCTAssertTrue(rename.issues(enabled: false, conditions: conditions).contains { $0.code == "find" })
        rename.find = "invoice"; rename.replacement = ""
        XCTAssertTrue(rename.issues(enabled: false, conditions: conditions).isEmpty)
    }
    func testMetadataRequiresActualChangeAndReplaceAcknowledgement() {
        var tags = ActionDraft(.metadata)
        XCTAssertFalse(tags.issues(enabled: false, conditions: conditions).isEmpty)
        tags.labelMode = .clear
        XCTAssertTrue(tags.issues(enabled: false, conditions: conditions).isEmpty, "A color-label change alone is sufficient")
        tags.labelMode = .unchanged
        tags.tagNames = ["Annual, reports"]
        XCTAssertTrue(tags.issues(enabled: false, conditions: conditions).isEmpty)
        tags.tagEntry = "Unadded"
        XCTAssertTrue(tags.issues(enabled: false, conditions: conditions).contains { $0.code == "pendingTag" })
        tags.tagEntry = ""; tags.tagsMode = .replace
        XCTAssertTrue(tags.issues(enabled: false, conditions: conditions).contains { $0.code == "replaceTags" })
        tags.replaceTagsAcknowledged = true
        XCTAssertTrue(tags.issues(enabled: false, conditions: conditions).isEmpty)
        tags.tagsMode = .unchanged; tags.labelMode = .clear; tags.tagEntry = "Dormant entry"
        XCTAssertTrue(tags.issues(enabled: false, conditions: conditions).isEmpty)
        tags.labelMode = .unchanged
        XCTAssertFalse(tags.issues(enabled: false, conditions: conditions).isEmpty)
    }
    func testGuardedEnablementAndScriptConfigApprovalInvalidation() {
        var deletion = ActionDraft(.delete)
        XCTAssertTrue(deletion.issues(enabled: false, conditions: conditions).contains { $0.code == "deleteAcknowledgement" })
        deletion.deleteAcknowledged = true
        XCTAssertTrue(deletion.issues(enabled: false, conditions: conditions).isEmpty)
        XCTAssertTrue(deletion.issues(enabled: true, conditions: conditions).contains { $0.code == "capability" })
        var script = ActionDraft(.script)
        script.script.file = .sample("/Sample/script.zsh")
        script.script.arguments = [.init(value: ""), .init(value: "a b, c; $(literal)")]
        script.acknowledgeScript(true)
        XCTAssertTrue(script.issues(enabled: false, conditions: conditions).isEmpty)
        XCTAssertTrue(script.issues(enabled: true, conditions: conditions).contains { $0.code == "capability" })
        script.script.arguments[1].value += "changed"
        XCTAssertFalse(script.scriptAcknowledged)
        XCTAssertTrue(script.issues(enabled: false, conditions: conditions).contains { $0.code == "scriptAcknowledgement" })
        for value in ["0", "601", "1.5", "NaN"] {
            script.script.timeout = value
            XCTAssertTrue(script.issues(enabled: false, conditions: conditions).contains { $0.code == "timeout" })
        }
        script.script.interpreter = .custom
        XCTAssertTrue(script.issues(enabled: false, conditions: conditions).contains { $0.code == "interpreter" })
    }
    func testReorderDeleteAndDuplicateKeepIndependentValuesAndIdentities() {
        let a = ActionDraft(.rename), b = ActionDraft(.metadata)
        var chain = ActionChainDraft(steps: [a,b])
        let saved = chain
        XCTAssertTrue(chain.move(b.id, by: -1))
        XCTAssertEqual(chain.steps.map(\.id), [b.id,a.id])
        XCTAssertTrue(chain.remove(a.id))
        XCTAssertFalse(chain.update(a.id) { $0.find = "stale" })
        XCTAssertTrue(chain.update(b.id) { $0.tagNames = ["Work"] })
        XCTAssertEqual(chain.steps[0].tagNames, ["Work"])
        XCTAssertTrue(saved.steps[1].tagNames.isEmpty)
        var script = ActionDraft(.script); script.script.arguments = [.init(value: "literal")]; script.acknowledgeScript(true)
        var delete = ActionDraft(.delete); delete.deleteAcknowledged = true
        let copy = ActionChainDraft(steps: [script,delete]).renewedIdentity()
        XCTAssertNotEqual(copy.steps[0].id, script.id)
        XCTAssertNotEqual(copy.steps[0].script.arguments[0].id, script.script.arguments[0].id)
        XCTAssertEqual(copy.steps[0].script.arguments[0].value, "literal")
        XCTAssertFalse(copy.steps[0].scriptAcknowledged)
        XCTAssertFalse(copy.steps[1].deleteAcknowledged)
    }
    func testCaptureSourceMustBeAnUnambiguousRegexAndInactiveOptionsDoNotBlock() {
        let regex = ConditionDraftNode.predicate(.init(operation: .regex, text: "(?P<year>[0-9]+)"))
        var rename = ActionDraft(.rename); rename.filenameTemplate = "{capture:year}"
        XCTAssertTrue(rename.issues(enabled: false, conditions: conditions).contains { $0.code == "capture" })
        rename.captureConditionID = regex.id
        XCTAssertTrue(rename.issues(enabled: false, conditions: .group(children: [regex])).isEmpty)
        XCTAssertTrue(rename.issues(enabled: false, conditions: .group(.any, children: [regex])).contains { $0.code == "capture" })
        rename.renameMode = .replace; rename.find = "old"; rename.replacement = "new"
        XCTAssertTrue(rename.issues(enabled: false, conditions: conditions).isEmpty, "Inactive template options must not invalidate find/replace")
    }
    func testSelectedLocalFilesKeepByteReferencesAndRejectDirectoriesAndLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("folder-master-action-selection-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("literal script.zsh")
        try Data("# synthetic fixture\n".utf8).write(to: file)
        let location = try ActionLocationDraft.file(file)
        XCTAssertTrue(location.isValid)
        XCTAssertFalse(location.sample)
        XCTAssertFalse(location.wasExecutable)
        XCTAssertEqual(location.path, try NativeFolderAccess.pathData(for: file))
        XCTAssertFalse(location.bookmark.isEmpty)
        XCTAssertThrowsError(try ActionLocationDraft.file(root))
        let link = root.appendingPathComponent("alias.zsh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try ActionLocationDraft.file(link))
        XCTAssertThrowsError(try ActionLocationDraft.file(file, executable: true))
        var action = ActionDraft(.script); action.script.file = location; action.script.interpreter = .executable
        action.acknowledgeScript(true)
        XCTAssertTrue(action.issues(enabled: false, conditions: conditions).contains { $0.code == "executable" })
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        action.script.file = try ActionLocationDraft.file(file, executable: true)
        action.acknowledgeScript(true)
        XCTAssertTrue(action.script.file!.wasExecutable)
        XCTAssertTrue(action.issues(enabled: false, conditions: conditions).isEmpty)
        XCTAssertThrowsError(try ActionLocationDraft.file(URL(string: "https://example.invalid/script")!))
    }

    func testStaleChooserCompletionCannotConsumeNewerRequest() throws {
        var chooser = ActionChooserRequest()
        let first = try XCTUnwrap(chooser.begin())
        XCTAssertNil(chooser.begin())
        chooser.invalidate()
        let second = try XCTUnwrap(chooser.begin())
        XCTAssertFalse(chooser.finish(first))
        XCTAssertEqual(chooser.id, second)
        XCTAssertTrue(chooser.finish(second))
        XCTAssertNil(chooser.id)
        XCTAssertFalse(chooser.finish(second))
    }
    func testChangingInterpreterToExecutableRequiresExecutableSelectionEvidence() {
        var action = ActionDraft(.script)
        action.script.file = .sample("/Sample/readable.zsh")
        action.script.interpreter = .executable
        action.acknowledgeScript(true)
        XCTAssertTrue(action.issues(enabled: false, conditions: conditions).contains { $0.code == "executable" })
    }

}

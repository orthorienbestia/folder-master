import Foundation

@main
struct AppModelSmoke {
    @MainActor static func main() {
        for shouldSave in [true, false] {
            let model = AppModel()
            model.exploreDemo()
            let originalID = model.selectedRuleID
            model.draft?.name = "Edited invoice rule"
            guard model.dirty else { fail("Editing did not become dirty") }
            model.selectRule(originalID)
            guard model.dirty, model.draft?.name == "Edited invoice rule" else {
                fail("Reselecting the current rule discarded unsaved edits")
            }
            model.addRule()
            guard model.showUnsaved else { fail("New Rule discarded dirty edits without prompting") }
            model.resolveUnsaved(save: shouldSave)
            guard model.experience.rules.count == 4 else { fail("Resolving edits lost the requested New Rule action") }
            guard model.selectedRuleID != originalID, model.draft?.name == "Untitled Rule", model.draft?.enabled == false else {
                fail("New Rule did not select an independent disabled draft")
            }
            guard model.experience.rules[0].name == (shouldSave ? "Edited invoice rule" : "File invoices") else {
                fail("Save/Discard did not preserve the requested edit behavior")
            }
        }
        print("Native presentation smoke passed: dirty-New Save and Discard preserve navigation intent")
    }
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

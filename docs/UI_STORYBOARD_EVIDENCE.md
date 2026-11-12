# Native storyboard evidence — 11 November 2026

This records partial M1 experience work under tasks 1.11/1.12 and later native configuration integration. It is not acceptance of a working organizer. The app still has no connected watcher, rule evaluator, file action executor, operational history or real undo. Earlier storyboard states below are visibly synthetic and session-only; file-result rows use a fixed invoice plan. The final section separately records real saved-rule UI evidence. Selecting or editing a rule does not evaluate it.

## Implemented presentation journey

1. Choose **Explore Sample Interface** from the real workspace. Downloads has three saved sample rules; Projects starts Off with no rules; Scans starts unavailable and Off. Each folder retains its own rule list and selection.
2. **Test Draft** opens a read-only sample preview. No checkboxes, Apply or simulation-run control appears. Escape closes it.
3. Toolbar **Preview** opens the saved-plan sample with Ready, Unknown and Needs review rows. Only complete Ready file chains can be selected. Inspecting a row shows its explanation and sample before/after paths.
4. Choose **Successful run**, **Partial move failure** or **Permission failure**, then **Review Selected**. The native confirmation names the selected chain count and sample outcome. Cancel starts no run. Confirmation pins the selected rows and scenario.
5. The sample provider records one file boundary every two seconds, independently of animation timing. Pause shows pending feedback until a current boundary settles; then it stops queued work if any remains. Resume continues the pinned remainder. Cancel retains already-recorded sample steps and prevents obsolete completions from overwriting a later preview.
6. Results distinguish completed/partial/failed/not-started counts. Partial failure retains a sample rename and tag while explaining the failed move. A permission-failure sample records no started effects.
7. History supports filename search, an attention filter and stable selected-record inspection. Its inspector shows step outcomes, before/after paths and inverse eligibility. A hidden filtered-out selection does not keep an unrelated inspector visible.
8. **Preview Sample Undo** shows reverse-order steps for a completed record. **Simulate Undo** appends an inverse record and keeps the original selected and marked as having an undo record. Partial, failed, already-undone and inverse records show an explicit reason instead of offering an unchecked inverse. There is no real fingerprint validation or filesystem inverse behind this sample.

## Verification performed

| Check | Observed result |
| --- | --- |
| Test-first confirmation regression | Before the guard, calling the provider directly started a run without confirmation; the added smoke failed. After the guard, unconfirmed/canceled/changed-selection approvals start no run |
| Test Draft isolation | Linked model smoke rejects run requests from draft preview; native sheet has no execution control |
| Partial failure regression | Failed first because partial outcome became successful. Provider now records one completed plus one partial chain and retained-step evidence |
| Pause regression | Failed with the unimplemented pause path; now one current boundary completes, the next waits, and resume produces no duplicate or changed confirmed chains |
| Inverse regression | Failed with no appended inverse; now the new record references the retained original, and a stale sheet cannot undo twice |
| Permission failure / blocked partial inverse | Linked model smoke verifies all selected permission-denied chains fail without differing before/after paths; partial inverse stays blocked |
| Cancellation and replacement | After cancel, a later draft preview stays in Review and receives no stale sample history completion |
| Native visual/AX journey | Inspected light-appearance Test Draft, saved preview, selected-chain confirmation, running/pending pause, partial results, history inspector, blocked inverse, completed inverse and repeated-undo blocking |
| Focus/selection | Escape dismissed draft/undo sheets; app remained usable. The selected original history row stayed selected after its inverse was appended. This is not a full keyboard or VoiceOver audit |
| Filter correction | Native inspection reproduced a completed inspector lingering after the attention filter hid that row. Lookup now uses visible filtered rows; repeated native inspection showed the selection prompt while only the partial row remained |
| Static review | Independent read-only reviewer found no blocker in the scoped provider/view/test changes; no runtime claim was made by the reviewer |

The UI used a fresh private debug data root and synthetic in-memory rows. No actual watched folder or document was enrolled. The test app exited normally. A read-only check found zero saved folders, runs, operation-journal rows and history rows in the isolated store; sample activity stayed in memory. The owned temporary store was then removed. Querying its AX state after Quit caused the UI tool to reopen the app, so exit cleanup used a running-app inventory without re-querying the closed target. This does not establish menu persistence or close/reopen correctness.

## Folder scope and unsaved navigation follow-up

The linked presentation smoke first reproduced shared rules leaking into Projects, then a new rule incorrectly appearing already saved. Folder rule/selection storage is now scoped by sample folder ID. A new disabled placeholder stays dirty; valid Save stores it in the session, while Discard removes it. Save/Discard/Keep Editing protects folder selection, history navigation and Leave Demo. An invalid Save does not dismiss the pending intent. Returning from Leave Demo preserves saved sample configuration until the app quits; nothing is written into the real folder/rule store.

Projects shows a native empty state and New Sample Rule action; Command-N also creates the disabled draft. Name/condition/action presence errors have inline explanations, with Save disabled for missing fields. These are structural storyboard checks, not complete typed/operator/template validation. A saved-rule preview with no enabled sample rules shows zero rows; Test Draft remains read-only. Sample paths and preview context use the captured selected folder rather than always displaying Downloads. An Off-folder sample confirmation explains that a simulation runs once without enabling that folder.

Scans demonstrates unavailable-folder guidance and **Simulate Reconnect**. The one-second asynchronous provider updates only that sample folder, leaves its enable state unchanged, and cannot steal selection from another folder. Token checks discard canceled reconnection completions. This performs no bookmark resolution, OS permission check, volume access or real reconnection.

| Follow-up check | Observed result |
| --- | --- |
| Linked regression smoke | Isolated rule lists/selected IDs survive navigation; new placeholders are dirty and removed on discard; empty/unavailable previews are guarded; Save/Discard/Keep Editing and Leave Demo preserve the intended state |
| Reconnect model checks | Pending state is explicit; navigating to Projects while it completes retains Projects selection and leaves Scans available but Off |
| Native folder journey | Projects displayed Off/empty; Command-N created an unsaved disabled draft; switching folders prompted with disabled Save for the invalid draft; Keep Editing stayed on Projects; Discard removed the placeholder and completed the requested switch |
| Native empty preview | Projects had 0 ready/unknown/review rows and disabled Review Selected; no invoice rows were invented for its empty saved-rule set |
| Native unavailable/reconnect | Scans displayed unavailable guidance with disabled preview/run; Simulate Reconnect returned an available, Off folder with its own disabled rule. The brief pending render was not captured in this native walkthrough |
| Deferred history navigation | An edited Downloads draft stayed separate from saved preview. View Demo History dismissed the preview first, then presented the unsaved dialog; Save opened history, and returning to Downloads showed the edited saved name |
| Independent review | Read-only reviewer found no blocker in the scoped folder/model/view/test changes; this was static review, not runtime proof |

The preview-to-history handoff uses the sheet's dismissal callback so it does not attempt to present a second modal while the preview is still open. The linked smoke also checks this sequencing. The follow-up native store contained zero folders/runs/operation-journal/history rows after normal app exit and was removed. These changes do not complete tasks 1.11/1.12; broader screen states, typed nested editing and experience verification remain below.

## Motion and remaining acceptance

Result transitions reuse the existing Follow System/Reduced/Off policy and opacity-only context transition. Partial/error/cancel/pause feedback applies immediately. No animation completion controls sample execution or undo. Unit checks cover the policy values, but no timing/frame trace or comprehensive visual motion acceptance was performed in this checkpoint.

Tasks **1.11 and 1.12 remain unchecked**. Remaining gates include native typed-action walkthroughs and complete validation; scan/empty/stale/permission preview states; complete settings/menu state coverage; minimum-size and dark-appearance captures; keyboard-only/VoiceOver journeys; reduced/off/interrupted-transition recordings and measurements. A first-time evaluator walkthrough has not run. Real execution, durable outcomes, dependency/fingerprint validation, all catalog controls and full app integration remain later implementation requirements, not substitutes for these sample screens.

## Structured condition editor follow-up

The sample rule form now offers Name, Extension, Kind, Size, Date, Finder tags, Finder color label and Text content controls within All/Any/None groups. Stable UUIDs preserve row identity across edits, move-up/down and deletion; copied rules receive new tree identities. Three group levels and fifty predicates are enforced. Inline structural checks block Save and Test Draft for empty values/groups, incompatible operators, reversed ranges, fractional-byte/overflow sizes and unfinished tag entry. Size conversion uses exact decimal arithmetic. This native form is not the Rust schema or evaluator: regex/glob compilation, UTType availability, actual Finder tag discovery and full engine validation remain pending. At this checkpoint action rows still contained free text; the following action-editor checkpoint replaces them.

Native light-appearance inspection selected all eight field families, rejected a 2–1 size range, accepted its correction, and kept Minimum/Maximum captions visible with populated inputs. A comma-containing tag was retained as one exact tag chip; pending entry blocked Save until Add. Any/None nesting reached the third level, where Add Group was disabled. Adding focused the new Name value; reordering retained its focus/value; deleting it moved focus to the surviving value, which accepted subsequent typing. A valid Save showed Saved to demo and disabled Save/Discard. These are scoped observations, not full keyboard/VoiceOver or motion acceptance.

Seven new XCTest methods failed against the initial stubs, then passed with implementation. Linked model mutation checks separately failed when either the 200-character name guard or structural condition validation was removed; both guards were restored and the smoke passed. Final native results: 22 passed, zero failed, one pre-existing invalid-UTF-8 fixture skip. The content-source enum moved to a shared adapter file; the separate network-denied OCR proof passed after that move. The isolated app exited, and its store contained zero folders, runs, journal or history rows; all rule edits stayed in memory.

Build and model checks: `make build`, `make presentation-smoke`, `make test`, `make check`, `make universal`. Current checkpoint results are in [PROGRESS.md](PROGRESS.md). The experience contract remains [UI_UX_DESIGN.md](UI_UX_DESIGN.md).

## Ordered action form — 12 November 2026

Every requested action now has native typed controls rather than a free-text row. Actions and script arguments retain stable UUIDs across edits and reordering; duplicate assigns independent identities and remaps regex capture sources. The native form rejects empty/oversized chains, actions after a terminal action, invalid roots/relative templates, missing find values, unfinished tags and missing acknowledgements. Label-only changes work without requiring a tag. Terminal actions force Stop; script/delete enablement is blocked while real capabilities remain unavailable. Acknowledgement text explicitly describes sample configuration, not executable authorization.

Destination/script/interpreter choosers use local metadata and bookmarks only. Request ownership prevents an old completion or Cancel from consuming a newer request. Loading, saving or discarding a rule changes its draft session so an old callback cannot change the reloaded draft. Input focus identifiers distinguish separate fields on the same action. Off uses an animation-disabled transaction; Reduced permits brief opacity without displacement. These policies are implemented, not measured interaction evidence.

Verification: full native model suite (33 passed, one existing volume skip), linked Save/session regressions, universal min-14 compilation and read-only review. Review regressions caught chooser ownership and interpreter-switch issues before correction. No action, script, actual plan or user document was executed by these checks. A disposable local file was used solely for selector metadata and executable-bit checks and removed by the test.

**At this checkpoint, interactive acceptance remained Not run.** CUA was unavailable. Offscreen AppKit hosting/cache captures were incomplete and do not establish the rendered interface, dark appearance, minimum size, focus behavior or accessibility. The ignored rendering experiment was not added as a passing test. Actual chooser cancellation, all action controls, keyboard-only/VoiceOver and motion interruption still need native verification. Tasks 1.11/1.12 remain unchecked, as do the Rust schema, planner and full action-management tasks.

## Live native action walkthrough and rule-entry correction — 12 November 2026

A later native-window inspection provider was available. A fresh private debug store was used; no user folder was enrolled. The actual running app, rather than the offscreen render helper, supplied the screenshots and accessibility tree. The picker successfully switched through Move, Copy, Rename, Tags/label, Compress ZIP, Uncompress ZIP, Trash, permanent delete and custom script. The observed default controls and missing-value explanations match those families. This does not cover every action option or effect.

Native control-state reads confirmed that Test Script was disabled, terminal actions disabled Add Action and Continue, and an acknowledged delete action still could not save with its rule enabled. Turning the rule Off removed the capability error and made Save available for its sample configuration. No file action or script was run, and this sample rule was not saved to the real store.

The walkthrough reproduced a concrete entry defect: after scrolling the invoice editor into its actions, New Rule retained that position and hid the new rule's Name. The editor now scrolls to its named top anchor when the selected rule ID changes and focuses Name only for a new draft. Repeating the same native steps showed Name in view with `AXFocused=1`. An ordinary Case sensitive checkbox edit retained an explicitly set scrollbar value of `0.52`; Save and ordinary typing do not change the observed rule ID and therefore do not trigger this entry handler. Source review found no important issue in this fix.

Reproduce manually: open Explore Sample Interface, scroll the rule editor down, then use New Rule. Name should be visible and focused. Scroll again and toggle Case sensitive; the editor should keep its position. The regression was observed before and after the source change, not inferred from compilation.

Local ignored evidence: `build/action-ui-before-fix-evidence.json` (22 records), `build/action-ui-after-fix-evidence.json` (4 records), and the original `build/native-ui-new-rule-before.png` / `build/native-ui-new-rule-after.png`. The PNG bytes match their retained screenshot hashes. The rule-entry before/after evidence IDs are `ev_f135e53b3f704b6846b337934e9a57249f6709fbbe29fc482d003b0c95f9cc70` and `ev_80e3b73b34de2f407c3bd3e3b33ddb78d1ec3b6791ae3b16d74ada90ece4c5ee`. A graceful Quit was requested and process exit confirmed; three owned test roots were verified to contain zero folders, rule revisions/heads, runs, journal and history rows where a database existed, then removed.

Remaining boundaries: current-OS arm64 and light appearance only; no real file effects, destination chooser acceptance, complete option matrix, keyboard-only/VoiceOver journey, dark/minimum-window verification or timing/interruption recordings. AXValue text-entry attempts changed the reported field value without demonstrating that the draft committed it; they are excluded as typing/Save evidence and need a genuine keyboard/VoiceOver follow-up. The provider's page-scroll action was unsupported, so a targeted helper used the same owned window's verified writable scrollbar. No global input events or system privacy/appearance settings were changed. Tasks 1.11/1.12 and the full UI integration requirements stay open.

## Real saved-rule configuration — 12 November 2026

A fixture seeder created one local folder with an untouched sentinel and two disabled name/rename rules through the real EngineClient API, then released ownership before launching the app with its isolated debug root. The Rules tab loaded both saved summaries and revision 1. An exact-process/window AXPress on Case sensitive changed the editor to Unsaved changes. Save Rule was inspected as enabled, then pressed. The list/header/footer acknowledged revision 2. A read-only database query independently found case_sensitive=true, two heads and three immutable revisions; no run/journal/history rows existed.

New Rule showed Untitled Rule at the top with Name `AXFocused=1`; invalid empty conditions/actions kept Save disabled. Discard returned to the previous saved revision 2 without creating a third head. After graceful Quit and confirmed process exit, relaunch retained revision 2 and Case sensitive `AXValue=1`. The live condition caption was corrected from synthetic form wording to saved local configuration. Both app instances used only the generated root; neither selected a user folder or executed a file action.

Ignored evidence: `build/native-rule-ui-evidence.json` (five records), `build/native-rule-ui-reopen-evidence.json` (one record), and exact screenshot `build/native-rule-persistence.png`, SHA-256 `80ed8d7f64501de5e552bf429d012120e90ffad88f4dcc67b2585a44163d92fb`. The initial arm64 and final universal builds have distinct artifact digests recorded by their providers. Sessions were closed and both owned processes exited. The UI root and one failed-regression root were inspected for unchanged generated input bytes/empty execution tables and removed.

This demonstrates real configuration persistence and truthful save feedback. It adds no keyboard text-entry, VoiceOver, dark/minimum-size, full chooser, timing/interruption or reduced/off-motion proof. Those native acceptance gates remain open; the broader app still has no connected matching, watching, preview, effects, operational history or undo.

## Save-time compiler feedback — 12 November 2026

An isolated store held two disabled synthetic rules and an untouched sentinel. A test-only historical document was given an invalid regex before launching the app, exercising the supported read-and-repair path. Exact-process/window checkbox and Save presses retained Unsaved changes, reported the condition error and left both persisted revisions at 1/disabled. The first screenshot exposed an off-screen inline error. Stable error anchors and a compiler-feedback observer now scroll the first error to the center; the repeated native check showed its red message directly below the condition's controls. Normal edits clear feedback without invoking the scroll. Source review found no important issue; sample/real helper wording was distinguished afterward and the internal JSON path was removed from the user-facing banner.

Ignored evidence: `build/compiler-ui-before-scroll.json` / `.png`, `build/compiler-ui-scroll-evidence.json` / `.png`. These captures prove the scroll/error behavior on current-OS arm64 in light appearance; the later wording-only changes have build/controller verification. Discard, graceful Quit and process absence were confirmed. Read-only database/content checks found no new revisions or sentinel changes; only the owned fixture roots were removed. No global input events were used. Keyboard typing, VoiceOver announcements/focus, dark/minimum-size layouts and motion/interruption timing remain unverified; tasks 1.11/1.12/5.11 remain open.

# Native storyboard evidence — 11 November 2026

This records partial M1 experience work under tasks 1.11/1.12. It is not acceptance of a working organizer. The app still has no connected watcher, rule evaluator, file action executor, operational history or real undo. Every result below is visibly synthetic, session-only, and based on a fixed invoice plan. Selecting or editing a rule does not evaluate it.

## Implemented presentation journey

1. Choose **Explore Sample Interface** from the real workspace.
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

## Motion and remaining acceptance

Result transitions reuse the existing Follow System/Reduced/Off policy and opacity-only context transition. Partial/error/cancel/pause feedback applies immediately. No animation completion controls sample execution or undo. Unit checks cover the policy values, but no timing/frame trace or comprehensive visual motion acceptance was performed in this checkpoint.

Tasks **1.11 and 1.12 remain unchecked**. Remaining gates include per-folder empty/unavailable storyboard states; nested typed condition/group/action editing and inline validation; scan/empty/stale/permission preview states; complete settings/menu state coverage; minimum-size and dark-appearance captures; keyboard-only/VoiceOver journeys; reduced/off/interrupted-transition recordings and measurements. A first-time evaluator walkthrough has not run. Real execution, durable outcomes, dependency/fingerprint validation, all catalog controls and full app integration remain later implementation requirements, not substitutes for these sample screens.

Build and model checks: `make build`, `make presentation-smoke`, `make test`, `make check`, `make universal`. Current checkpoint results are in [PROGRESS.md](PROGRESS.md). The experience contract remains [UI_UX_DESIGN.md](UI_UX_DESIGN.md).

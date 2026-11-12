# Native rule persistence

Connect the reviewed native condition/action controls to the typed Rust configuration API. This advances task 2.1; matching, compilation, file effects and full experience acceptance remain separate required work.

1. Add a bidirectional schema-v1 adapter preserving all active options, UUIDs, byte paths/bookmarks, exact byte thresholds, calendar dates and literal script arguments. Sample references cannot cross into real persistence. Local script/delete acknowledgements never become execution approvals.
2. Add native engine validate/save/get/list methods and a dedicated observed real-rule controller. Read summaries first and one selected definition at a time. Keep drafts independent from immutable saved revisions. Reject stale saves without discarding edits; refresh requires deliberate discard.
3. Add a Rules tab beside folder setup using the existing native editors. New rules start disabled; enabled configuration explicitly does not activate automation in this build. Show loading/empty/error/saved states, truthful revision feedback and native Save/Discard/Keep Editing navigation. Preserve focus/scroll on ordinary edits.
4. Integrate folder selection, demo entry, removal and Quit with both dirty/pending folder and rule state. Prevent delayed chooser/load responses replacing a newer draft. Drain acknowledged configuration commands asynchronously before quitting.
5. Verify schema parity through real Swift→Rust→SQLite→Swift reopen fixtures for all families, stale saves and no file effects; test controller state transitions. Run native/Rust checks, linked regressions, universal build and scoped review. Record interactive checks separately; commit locally.

No product requirement is dropped. Rule deletion/reordering, pattern compilation, operational enablement and preview/execution are still on the canonical OpenSpec checklist. Task 2.1 is checked only when its full typed editor/persistence acceptance is established.

## Verified checkpoint — 12 November 2026

All five implementation steps above are complete for configuration persistence. Domain/model/editor-limit checks and 72 real Swift→Rust→SQLite roundtrips establish task 2.1. Full operational and native experience acceptance is still on its separate tasks.

`make test bridge-smoke persistence-smoke rule-persistence-smoke presentation-smoke check universal` passed: 47 Rust and 37 native tests, zero failures, one existing physical invalid-UTF-8 fixture skip. The typed native roundtrip includes all condition operators/action families, alternate metadata/script/date/content options, maximum sizes/display units, paging, stale saves, deliberate reload, script metadata and stable argv state. Native UI confirmed real Save/revision acknowledgement, New/Discard/focus and persisted state after relaunch. See PROGRESS.md and UI_STORYBOARD_EVIDENCE.md for actual scope and remaining checks.

Independent source review found label ordering, independent ZIP capture sources and executable-evidence reload issues; regressions/fixes and follow-up review resolve them. A separate failing save-state regression led to retaining native form identities/session acknowledgements only after the returned wire definition matches. No execution approval, content access or effect is inferred from that state.

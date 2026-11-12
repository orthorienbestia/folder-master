# Rust typed rule schema and revision storage

**Goal:** Persist validated typed rule definitions through the existing Rust worker; begin task 2.1 without connecting file effects or closing remaining UI/platform gates.

**Source contract:** USER_OPTIONS.md sections 2–4, OpenSpec rule-engine/file-actions specs, TDD D2/D5. The reviewed native forms inform the schema. Full UI, pattern compilation, metadata discovery, planning and execution acceptance remain open.

## Design

- `engine/src/rules.rs`: strict schema-v1 Serde types. Canonical UUID strings identify rules, groups, predicates and actions. Root All/Any/None; eight typed predicate families; nine typed action families; Stop/Continue. Field-specific operator enums prevent cross-family combinations. Unsupported versions/unknown fields/duplicate known fields are rejected.
- Raw document bytes enter `validate_rule` / `save_rule` so an intermediate JSON map cannot silently discard duplicate fields. Pure validation reads no files and executes no code. Size thresholds use u64 bytes with retained display unit; elapsed ages retain finite numeric amount/unit; calendar dates are Gregorian components and absolute times are Unix milliseconds.
- Locations retain opaque base64 byte paths/bookmarks. Validate encoding and absolute/NUL-free path shape only; native locality, identity, availability, permissions and executable checks remain mandatory later. No fake sample-location flag or sample acknowledgement becomes execution authorization.
- Validate required values, UUID uniqueness, group depth 3, leaves 50, actions 1–20, date/size bounds, exact tag lists, terminal ordering and Stop behavior. Tags/label must describe a change. Guarded rules cannot enable while capabilities are unavailable. Patterns/templates/captures are stored as typed configuration; full compilation remains task 2.4 and is required before operational use.
- Reuse schema-v1 rule revision/head tables. `save_rule(folder_id, expected_revision, definition)` creates revision 1 only for an unused ID; updates require the current revision and original folder and append an immutable revision transactionally. New heads append in creation order; updates preserve it. Explicit reordering is later work.
- `get_rule(id, optional revision)` returns one typed revision; `list_rules(folder_id, offset)` returns bounded summaries rather than multiplying full documents. The existing rule-head foreign-key cascade already removes current heads on folder removal; reuse it while retaining historical definitions. Reject incompatible stored documents without rewriting them.
- Keep existing low-level snapshot methods for the M1 storage contract; new worker commands use only typed methods. The main window remains on the visibly synthetic provider until actual rule management is wired.

## Checks and ownership

1. [x] Write failing domain contracts for all families, invalid field/operator pairs, versions/unknowns/duplicates, group/count/ID limits, invalid values and guarded/terminal behavior; implement the model.
2. [x] Write failing store contracts for reopen roundtrip, immutable history, stale saves, missing/cross-folder saves and folder removal; implement typed APIs.
3. [x] Write failing C-bridge contracts for validate/save/get/list, malformed nested documents and restart; implement commands with the same envelope/cancellation/ownership rules.
4. [x] Run full tests, formatting/Clippy/OpenSpec, linked native regression smoke and universal build. Review the scoped diff; update evidence and commit.

## Evidence — 12 November 2026

Domain tests initially failed 9/10; storage failed 5/5; bridge failed 4/4 before implementation. An additional fieldless-variant test failed before changing tagged unit variants to empty structs. The worker's internally tagged buffering also rejected valid raw definition payloads; direct strict command parsing preserves those bytes. Review's incompatible-head update regression failed before validating the existing revision inside its save transaction, then passed; follow-up source review found no remaining issue.

Final Rust suite: 47 passed, including 13 pure schema, five typed storage and five typed C-bridge tests. Native regression: 33 passed, one existing physical invalid-UTF-8 fixture skip. Linked presentation smoke, static/OpenSpec checks and universal build passed; both app/debug-dylib slices have macOS 14.0 minimum and local signature verifies. Ignored logs: `build/rule-schema-rust-final.log`, `rule-schema-full-test.log`, `rule-schema-presentation.log`, `rule-schema-check.log`, `rule-schema-universal.log`. The explicit schema JSON example is `engine/tests/support/rule_fixture.rs`; API documentation is in DEVELOPMENT.md.

**Current scope boundary:** This is a durable typed configuration foundation, not a matcher or organizer. No watch, script, file effect, planner/history/undo or real editor integration is implied. Task 2.1 stays unchecked until its complete persistence/editor contract is demonstrated; tasks 1.11/1.12 remain open.

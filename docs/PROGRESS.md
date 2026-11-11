# Folder Master — Progress and evidence

Last updated: 11 November 2026. Status: **active implementation — M1 foundation; 5/65 engineering tasks complete**. Real folder setup persists locally, but the app is not yet a working file organizer. The basic staged-script proof passes; full script isolation remains a failing gate.

## Objective and constraints

Build a local macOS 14+ menu bar folder organizer with every matcher/action requested in the [PRD](PRD.md), native SwiftUI/AppKit interface and Rust engine. User selected direct distribution and requested Git progress tracking. Prepare PRD/TDD/flows/options through OpenSpec before product implementation.

User expanded the goal to prioritize **UI, UX, animations and transitions**. The revised [tracked goal](GOAL.md) and [UI/UX design](UI_UX_DESIGN.md) make these acceptance requirements from M1. The active Codex goal remains active; available goal tooling can change status but cannot edit its objective text.

Current OpenSpec change: [build-folder-master](../openspec/changes/build-folder-master/proposal.md). Canonical engineering checklist: [tasks.md](../openspec/changes/build-folder-master/tasks.md). Keep checkboxes unchecked until the described behavior and verification exist.

## Stage ledger

| Stage | Status | Evidence / remaining gate |
| --- | --- | --- |
| Workspace inspection | Done | Greenfield; initial contents were OpenSpec config/placeholders and installed local skills; no source/tests/build targets |
| User architecture decisions | Done | Rust engine + native UI; direct distribution selected in chat |
| Primary-source research | Done for planning | Apple native UI/OCR/filesystem/security docs and Context7 Notify lookup; see RESEARCH.md |
| Local Git initialization | Done | Planning baseline a211aec on main; implementation branch feat/native-foundation; no remote |
| PRD / TDD / options / flows / UI-UX-motion | Planning baseline delivered | Independent planning review completed; apply started after the goal continuation request |
| OpenSpec proposal/specs/tasks | Apply in progress | Eight capabilities, 46 requirements, 86 scenarios; tasks 1.1, 1.2, 1.4, 1.9 and 1.10 complete, 60 tasks remain |
| M1 platform/experience foundation | In progress | Builds, bridge, storage/ownership and basic staged-script XPC proof verified; full script IPC-isolation gate fails; lifecycle, full UX/motion and metadata/OCR gates remain open |
| M2 safe metadata automation | Not started | No runtime checks |
| M3 complete content/actions | Not started | Script isolation/metadata/OCR remain unproven |
| M4 native management | Early integration | Real folder setup and M1 synthetic screens exist; reconnect, full rules/actions, management and real execution UX are pending |
| M5 release candidate | Not started | Performance, OS/architecture/signing/notarization evidence absent |

## Verification ledger

| Check | Result | Evidence |
| --- | --- | --- |
| OpenSpec context and empty initial capability inventory | Passed | CLI resolved this workspace; no existing capabilities/changes before proposal |
| OpenSpec artifact status | Passed | CLI reports 4/4 planning artifacts complete |
| Strict OpenSpec validation | Passed | openspec validate build-folder-master --strict |
| Local Markdown links / capability-task consistency | Passed at planning baseline | 20 Markdown files, zero broken local links; eight specs; 65 unique task IDs. Checkpoint verification recorded below |
| Independent builder questions | Passed after revisions | Reviewer confirmed previous gaps resolved; nothing material left in reviewed planning scope |
| Final Git diff / whitespace | Passed after correction | Authored scope reviewed; one trailing-space finding corrected before baseline commit |
| Rust foundation/storage suite | Passed | make test: 24 tests (3 unit, 8 bridge, 3 persistent bridge, 10 storage), no failures |
| Native XCTest | Passed with explicit skip | make test: 6 passed, 0 failed, 1 skipped. Physical invalid-UTF-8 directory fixture unsupported by this test volume; byte-level URL roundtrip passes |
| Swift↔Rust smoke | Passed | Real linked actor/ABI: status, pause, concurrent correlation, raw path bytes, invalid command, pre-canceled request and shutdown |
| Native presentation regression smoke | Passed | Dirty-New/reselect, pending folder-save navigation guards and reusing an already-open store during initialization; regressions reproduced before fixes |
| Native persistence regression smoke | Passed | Actual Swift/Rust/SQLite: enroll, revisioned settings save, restart, pause persistence, second-owner rejection/retry and settings-only removal; original fixture bytes unchanged |
| Rust formatting/static checks | Passed | make check: cargo fmt and clippy --all-targets -D warnings |
| Universal debug build | Passed | arm64 + x86_64 app slices, 14.0 minimum in app/debug dylib; native test binary minimum also 14.0 |
| Native screen inspection | Partial | Prior synthetic journey plus new real empty workspace→native chooser→setup sheet→Cancel, returning to zero folders. Only a generated empty fixture selected; no user documents enrolled |
| Lifecycle / full UX-motion / accessibility | Not fully verified | Close/menu reopening was inconclusive due UI tool refresh behavior; full motion/keyboard/VoiceOver/state matrix still open |
| Foundation code review | Fixes verified | Read-only reviewer found cancellation forwarding and dirty-New intent defects; both reproduced and fixed; follow-up found no material issue in those changes |
| Persistence/UI code review | Fixes verified | Read-only reviewer found pending-save navigation and initialization-retry defects; both reproduced, fixed and covered by the native model smoke; follow-up found no actionable issue in reviewed fixes/wiring |
| Basic staged-script XPC proof | Passed | make script-proof: synthetic staged zsh, literal argv, original read/write denial, malformed/future messages, link/oversized output rejection, nonzero exit, bounded logs and ~1.01s timeout |
| Strict script-isolation acceptance | Failed — scripts unavailable | Exact unentitled probe: host socket/Mach lookup succeed; script child socket fails EPERM but Launch Services lookup succeeds. No brokered launch/upload message sent; see SCRIPT_PROOF.md |
| Script proof review | Corrected test validated | Reviewer identified confounded sandbox-entitled child; replaced with the same unentitled binary inside/outside sandbox. Follow-up found no new material issue in corrected scope |
| Script proof universal build/signature | Passed | Host, XPC helper and unentitled probe each contain arm64/x86_64 with minos 14.0; nested codesign --verify --deep --strict passes. This is not Intel/macOS-14 runtime evidence |
| Queued post-submit cancellation through Swift | Not deterministically verified | Pre-canceled native mutation proved rejected; queued worker cancellation separately tested in Rust; current commands are atomic/fast |
| OCR / script sandbox / Finder / volume validation | Partial / gates open | Basic script sandbox proof and folder adapters exist. Full script privacy/authentication, denied TCC, cloud placeholders, disconnected/remote volumes, metadata actions and OCR remain unproven |
| Benchmarks / macOS runtime matrix / release signing | Not run | Targets and gates only |

## Git operating rules

- Keep a coherent reviewed planning baseline on main. Use focused feat/<topic> branches for implementation; no remote/push is implied by Git tracking.
- Include relevant task IDs and passed/not-run checks in commit descriptions and progress entries. Update task state in the same change as the verified work.
- Preserve pre-existing local tooling; exclude installed .agents skills, build outputs, credentials and real user documents. Only synthetic curated fixtures enter source control.
- Inspect status/diff before staging, stage paths intentionally and verify clean status after commit. Do not manufacture commit IDs or claim work is implemented from a documentation-only commit.

## Next gate

Continue M1: finish lifecycle/storyboard acceptance and folder/TCC/placeholder, metadata and OCR adapters. Investigate a supported script-isolation mechanism that closes the failed IPC gate without narrowing compatibility; keep scripts off. Reuse storage/ownership for durable journaling before real file effects. Completing the foundation does not fulfill the full app goal.

## Planning review decisions

The independent builder review identified five material questions, all resolved in the package: reject remote mounted storage; do not automatically run already-true historical time rules; finish the current approved chain after moving outside watch scope, then stop later rules; preflight guarded capabilities for the entire chain; require exclusive store ownership before recovery/writes.

Additional consistency fixes: regex requires complete text; started chains retain pinned revisions while honoring live pause/disable; multiply-linked tag/label inputs are blocked; operational eligibility receipts outlive history retention. The reviewer reread these changes and the expanded UI/UX/motion contract and reported no remaining material questions. This is design review, not a runtime/security certification.

## M1 foundation checkpoint — 11 November 2026

- Actual tools: Xcode 26.0.1 (17A400), SDK 26.0, Swift 6.2, Rust/Cargo 1.89.0, XcodeGen 2.46.0; host arm64 macOS 26.6.2. Rust toolchain/dependencies locked; x86_64 standard library installed for cross-compilation.
- Product source: engine/ holds the static library; native/ holds the C header, actor wrapper, SwiftUI app and tests; scripts/ and Makefile provide repeatable offline builds. See DEVELOPMENT.md for exact commands and ABI lifetime rules.
- Real implemented behavior: bounded worker protocol, owned buffer release, correlated replies, cancellation boundary, panic guards, local engine pause acknowledgements and shutdown.
- Presentation at this first checkpoint: native main window/status menu/settings, editable sample rules, synthetic preview/result/history and motion policy. No watcher, action execution, actual OCR, durable history or undo is claimed. Sample rule syntax remains free text; sample folders share an illustrative rule list, and nested groups/typed editors/full state matrix are future work.
- Red/green evidence: seven initial Rust contracts failed against the stub then passed; three native state tests failed against stubs then passed. Review regressions failed for pre-canceled mutation dispatch and dirty-New navigation before fixes. An additional failing same-rule-reselect test exposed discarded edits and was corrected.
- Checks remain separate: universal compilation is not Intel/macOS-14 runtime proof; ad-hoc code signature is not hardened/notarized release readiness; inspecting the storyboard is not completed UI/UX acceptance.

## M1 persistence and real folder setup checkpoint — 11 November 2026

- Tasks 1.9/1.10: schema-v1 tables, transactional migration, private local WAL/FULL SQLite, immutable internal rule snapshots/settings, WAL-safe consistent backup and exclusive kernel lease before opening the database. Journal/history/receipt/deadline tables are provisioned; operational APIs, effects/recovery and user-facing backup/restore remain subsequent tasks.
- Real native setup: choose an eligible directory, review its path/name, save disabled configuration, edit scope/preferences with revision checks, guard unsaved navigation, and remove configuration without removing files. New scopes reject duplicates/nesting/app-data overlap. Folder records and pause state survive engine restart. Watching, rule evaluation and Run Now remain unavailable; the sample interface is separate and labeled.
- Native adapter evidence: directory/link/package checks, ordinary bookmark resolving after rename, raw-byte CFURL roundtrip. Physical invalid-UTF-8 directory creation fails with EILSEQ on this volume, including an outside-sandbox probe; XCTest reports that fixture skipped. No claim of denied-TCC, remote/disconnected volume, reconnect or cloud hydration acceptance; tasks 1.6/5.1 remain unchecked.
- Safety evidence: a failed migration after earlier DDL preserves sentinel data and leaves schema version unchanged; a future database version leaves database bytes unchanged; online backup includes uncheckpointed WAL and refuses replacement; second owners cannot issue configuration/pause writes; process kill releases ownership without replacing the lock inode.
- UI/UX remains part of the goal. The real setup reuses native controls, explicit loading/error/retry and pending/saved feedback, and motion policy. Review found save/navigation and initialization retry races; failing regressions were reproduced and corrected. CUA inspected the empty workspace, native chooser, setup sheet and cancellation. Full keyboard/VoiceOver, normal/reduced/off transitions, minimum-window and flow acceptance remain open.
- Motion settings still use AppStorage in this foundation, guarded by store availability; full Rust-owned settings/export/retention acceptance is pending M4. Generic rule snapshots are not a completed typed rule editor. No document contents are stored/uploaded by setup; other sync software is outside the app's control.

## VS Code toolchain compatibility — 11 November 2026

- User reported the extension's blocking old-toolchain dialog. The pinned toolchain omitted rust-analyzer, and `rustup run 1.89.0 rust-analyzer --version` failed because the component was absent.
- Added rust-analyzer alongside rustfmt/Clippy in rust-toolchain.toml and installed the official matching component. Rust compiler remains 1.89.0. `cargo check --offline --locked --workspace --all-targets` and the matched analyzer's complete diagnostic scan pass (normal inactive-test-code hints remain).
- Restarted the server in the actual VS Code workspace; **Show RA Version** reports 1.89.0 from the pinned toolchain. The original blocking dialog is resolved. Extension 0.3.3113 still emits a non-blocking `implicitDrops` configuration warning because its current string default is newer than this server's boolean schema; it does not prevent analysis. No unrelated Gemini/Todo Tree extension notifications were changed.

## M1 staged-script feasibility checkpoint — 11 November 2026

- Task 1.4: separate locally signed `ScriptProof` host/XPC helper with App Sandbox, fixed synthetic input, no filesystem/network callback to the host, staged zsh/literal argv, descriptor-based output validation and negative cases. The initially unavailable runner produced a failing integration test before implementation. Detailed scope and commands: [SCRIPT_PROOF.md](SCRIPT_PROOF.md).
- Task 1.5 remains unchecked. A separately built probe with no sandbox entitlement reaches a local listener and Launch Services outside the helper; the same binary as a zsh child is denied direct networking (errno 1) but still obtains the Launch Services Mach port. The strict acceptance command fails; port lookup is not proof of brokered egress, and the test sends no message to another application.
- Static review caught the first probe's confounded executable entitlement. The corrected exact-binary comparison reproduces the finding and the reviewer found no additional material defect in that corrected scope. No product target, rule command, script enable control or unrestricted fallback was added.
- Ad-hoc helper authentication checks UID and bundle ID only; release Team-ID anchoring remains unproven. Host-static-resource/live-process inspection is denied by the helper sandbox; no filesystem exception was added to bypass this. Full external quotas, escaped-session descendants, custom interpreters, macOS 14/Intel runtime checks and public release signing remain open.
- This changes the next script engineering step: investigate and revise the isolation mechanism while preserving the offline and compatibility requirements. Work on independent M1 native/UX/OCR gates can continue; the overall app goal remains active.

# Folder Master — Progress and evidence

Last updated: 11 November 2026. Status: **active implementation — M1 foundation; 2/65 engineering tasks complete**. The app builds, but it is not yet a working file organizer.

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
| OpenSpec proposal/specs/tasks | Apply in progress | Eight capabilities, 46 requirements, 86 scenarios; tasks 1.1 and 1.2 complete, 63 tasks remain |
| M1 platform/experience foundation | In progress | Pinned Rust/native builds and C bridge verified; synthetic storyboard inspected; lifecycle, full UX/motion, script/metadata/OCR/storage gates remain open |
| M2 safe metadata automation | Not started | No runtime checks |
| M3 complete content/actions | Not started | Script isolation/metadata/OCR remain unproven |
| M4 native management | Not started | Early M1 synthetic screens exist; complete native management and real engine UX are pending |
| M5 release candidate | Not started | Performance, OS/architecture/signing/notarization evidence absent |

## Verification ledger

| Check | Result | Evidence |
| --- | --- | --- |
| OpenSpec context and empty initial capability inventory | Passed | CLI resolved this workspace; no existing capabilities/changes before proposal |
| OpenSpec artifact status | Passed | CLI reports 4/4 planning artifacts complete |
| Strict OpenSpec validation | Passed | openspec validate build-folder-master --strict |
| Local Markdown links / capability-task consistency | Passed | 20 Markdown files, zero broken local links; eight specs; 65 unique task IDs, two completed |
| Independent builder questions | Passed after revisions | Reviewer confirmed previous gaps resolved; nothing material left in reviewed planning scope |
| Final Git diff / whitespace | Passed after correction | Authored scope reviewed; one trailing-space finding corrected before baseline commit |
| Rust foundation suite | Passed | make test: 11 tests (3 worker/guard unit tests, 8 real bridge contract tests), no failures |
| Native XCTest | Passed | make test: 3 tests for motion restriction, safe selection and independent disabled duplication, no failures |
| Swift↔Rust smoke | Passed | Real linked actor/ABI: status, pause, concurrent correlation, raw path bytes, invalid command, pre-canceled request and shutdown |
| Native presentation regression smoke | Passed | Dirty-New Save/Discard navigation and same-rule reselect preserve edits; failures reproduced before fixes |
| Rust formatting/static checks | Passed | make check: cargo fmt and clippy --all-targets -D warnings |
| Universal debug build | Passed | arm64 + x86_64 app slices, 14.0 minimum in app/debug dylib; native test binary minimum also 14.0 |
| Native storyboard inspection | Partial | CUA verified welcome→rule editor→synthetic preview/progress/result→history and ready-only row selection; no real files used |
| Lifecycle / full UX-motion / accessibility | Not fully verified | Close/menu reopening was inconclusive due UI tool refresh behavior; full motion/keyboard/VoiceOver/state matrix still open |
| Foundation code review | Fixes verified | Read-only reviewer found cancellation forwarding and dirty-New intent defects; both reproduced and fixed; follow-up found no material issue in those changes |
| Queued post-submit cancellation through Swift | Not deterministically verified | Pre-canceled native mutation proved rejected; queued worker cancellation separately tested in Rust; current commands are atomic/fast |
| OCR / script sandbox / Finder / volume validation | Not run | No adapters or sandbox service implemented yet |
| Benchmarks / macOS runtime matrix / release signing | Not run | Targets and gates only |

## Git operating rules

- Keep a coherent reviewed planning baseline on main. Use focused feat/<topic> branches for implementation; no remote/push is implied by Git tracking.
- Include relevant task IDs and passed/not-run checks in commit descriptions and progress entries. Update task state in the same change as the verified work.
- Preserve pre-existing local tooling; exclude installed .agents skills, build outputs, credentials and real user documents. Only synthetic curated fixtures enter source control.
- Inspect status/diff before staging, stage paths intentionally and verify clean status after commit. Do not manufacture commit IDs or claim work is implemented from a documentation-only commit.

## Next gate

Continue M1: finish lifecycle and storyboard acceptance; build the signed restricted script-service feasibility proof, native folder/metadata/OCR adapters, schema-v1 storage and exclusive writer ownership. Real file effects must wait for durable journaling/safety work; completing the foundation does not fulfill the full app goal.

## Planning review decisions

The independent builder review identified five material questions, all resolved in the package: reject remote mounted storage; do not automatically run already-true historical time rules; finish the current approved chain after moving outside watch scope, then stop later rules; preflight guarded capabilities for the entire chain; require exclusive store ownership before recovery/writes.

Additional consistency fixes: regex requires complete text; started chains retain pinned revisions while honoring live pause/disable; multiply-linked tag/label inputs are blocked; operational eligibility receipts outlive history retention. The reviewer reread these changes and the expanded UI/UX/motion contract and reported no remaining material questions. This is design review, not a runtime/security certification.

## M1 foundation checkpoint — 11 November 2026

- Actual tools: Xcode 26.0.1 (17A400), SDK 26.0, Swift 6.2, Rust/Cargo 1.89.0, XcodeGen 2.46.0; host arm64 macOS 26.6.2. Rust toolchain/dependencies locked; x86_64 standard library installed for cross-compilation.
- Product source: engine/ holds the static library; native/ holds the C header, actor wrapper, SwiftUI app and tests; scripts/ and Makefile provide repeatable offline builds. See DEVELOPMENT.md for exact commands and ABI lifetime rules.
- Real implemented behavior: bounded worker protocol, owned buffer release, correlated replies, cancellation boundary, panic guards, local engine pause acknowledgements and shutdown.
- Presentation: native main window/status menu/settings, editable sample rules, synthetic preview/result/history and motion policy. No watcher, user-file read, action execution, actual OCR, durable history or undo is claimed. Sample rule syntax remains free text; all folders currently share the same illustrative rule list, and nested groups/typed editors/full state matrix are future work.
- Red/green evidence: seven initial Rust contracts failed against the stub then passed; three native state tests failed against stubs then passed. Review regressions failed for pre-canceled mutation dispatch and dirty-New navigation before fixes. An additional failing same-rule-reselect test exposed discarded edits and was corrected.
- Checks remain separate: universal compilation is not Intel/macOS-14 runtime proof; ad-hoc code signature is not hardened/notarized release readiness; inspecting the storyboard is not completed UI/UX acceptance.

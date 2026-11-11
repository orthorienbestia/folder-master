# Folder Master — Progress and evidence

Last updated: 11 November 2026. Status: **planning validated and builder-reviewed; ready for user review; implementation not started**.

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
| Local Git initialization | Done | main initialized; no remote; planning baseline tracked by local commit history |
| PRD / TDD / options / flows / UI-UX-motion | Ready for user review | Linked from README; independent builder review reported no remaining material questions after corrections |
| OpenSpec proposal/specs/tasks | Planning complete | Four artifact categories; eight capabilities, 46 requirements, 86 scenarios; 65 engineering tasks all unchecked |
| M1 platform feasibility | Not started | No product scaffolding or dependencies installed |
| M2 safe metadata automation | Not started | No runtime checks |
| M3 complete content/actions | Not started | Script isolation/metadata/OCR remain unproven |
| M4 native management | Not started | Screens are design contracts only |
| M5 release candidate | Not started | Performance, OS/architecture/signing/notarization evidence absent |

## Verification ledger

| Check | Result | Evidence |
| --- | --- | --- |
| OpenSpec context and empty initial capability inventory | Passed | CLI resolved this workspace; no existing capabilities/changes before proposal |
| OpenSpec artifact status | Passed | CLI reports 4/4 planning artifacts complete |
| Strict OpenSpec validation | Passed | openspec validate build-folder-master --strict |
| Local Markdown links / capability-task consistency | Passed | 19 Markdown files, zero broken local links; eight specs; 65 unique unchecked task IDs |
| Independent builder questions | Passed after revisions | Reviewer confirmed previous gaps resolved; nothing material left in reviewed planning scope |
| Final Git diff / whitespace | Passed after correction | Authored scope reviewed; one trailing-space finding corrected before baseline commit |
| Rust/native compilation and unit/integration/UI tests | Not run | No app source yet |
| OCR / script sandbox / Finder / volume validation | Not run | Documentation is not runtime proof |
| Benchmarks / macOS runtime matrix / release signing | Not run | Targets and gates only |

## Git operating rules

- Keep a coherent reviewed planning baseline on main. Use focused feat/<topic> branches for implementation; no remote/push is implied by Git tracking.
- Include relevant task IDs and passed/not-run checks in commit descriptions and progress entries. Update task state in the same change as the verified work.
- Preserve pre-existing local tooling; exclude installed .agents skills, build outputs, credentials and real user documents. Only synthetic curated fixtures enter source control.
- Inspect status/diff before staging, stage paths intentionally and verify clean status after commit. Do not manufacture commit IDs or claim work is implemented from a documentation-only commit.

## Next gate

User review of the concrete planning package. The OpenSpec proposal skill explicitly requires stopping after planning artifacts; start product work via OpenSpec apply on a subsequent request. Planning completion does not fulfill the app-build goal.

## Planning review decisions

The independent builder review identified five material questions, all resolved in the package: reject remote mounted storage; do not automatically run already-true historical time rules; finish the current approved chain after moving outside watch scope, then stop later rules; preflight guarded capabilities for the entire chain; require exclusive store ownership before recovery/writes.

Additional consistency fixes: regex requires complete text; started chains retain pinned revisions while honoring live pause/disable; multiply-linked tag/label inputs are blocked; operational eligibility receipts outlive history retention. The reviewer reread these changes and the expanded UI/UX/motion contract and reported no remaining material questions. This is design review, not a runtime/security certification.

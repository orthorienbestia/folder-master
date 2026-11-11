# Folder Master

Planned macOS 14+ menu bar file organizer: a **Rust engine with native SwiftUI/AppKit UI**, local OCR and direct distribution. Documents and file processing stay on the Mac.

**Current state: planning baseline. No app code or runnable build yet.**

[Updated project goal](docs/GOAL.md): native UI/UX, animations and transitions are first-class acceptance requirements alongside engine correctness and privacy.

## Read the plan

1. [Product requirements (PRD)](docs/PRD.md) — scope, requested features, acceptance criteria and delivery gates.
2. [Technical design (TDD)](openspec/changes/build-folder-master/design.md) — architecture, data model, file safety, OCR/scripts, recovery, undo and verification.
3. [User flows and screen contract](docs/USER_FLOWS.md) — onboarding, editor, automatic/manual execution, conflicts, history and undo.
4. [All user-visible options](docs/USER_OPTIONS.md) — controls, operators, defaults, constraints and action semantics.
5. [Research and sources](docs/RESEARCH.md) — current primary documentation and unverified platform assumptions.
6. [Progress and evidence](docs/PROGRESS.md) — actual stage status and Git workflow.
7. [UI/UX, animations and transitions](docs/UI_UX_DESIGN.md) — visual system, screen states, motion matrix, accessibility and usability checks.

## OpenSpec

Active change: [build-folder-master](openspec/changes/build-folder-master/proposal.md). Eight [capability specs](openspec/changes/build-folder-master/specs) define testable behavior; [implementation tasks](openspec/changes/build-folder-master/tasks.md) are unchecked until implemented and verified.

```sh
openspec status --change build-folder-master
openspec validate build-folder-master --strict
git status --short
git log --oneline
```

Review the planning package before starting the OpenSpec apply workflow. Script isolation, native metadata preservation and target-OS compatibility have explicit early feasibility gates. A plan passing validation is not proof of runtime behavior.

## Git tracking

Local Git repository on `main`; no remote configured or publishing requested. Planning is the first focused commit. Future implementation uses focused feature branches, commits linked to task numbers and evidence updates in [PROGRESS.md](docs/PROGRESS.md). Generated builds, real documents, credentials and local tool state do not belong in commits. Installed `.agents` skills remain local workspace tooling.

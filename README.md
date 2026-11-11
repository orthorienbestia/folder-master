# Folder Master

macOS 14+ menu bar file organizer in development: a **Rust engine with native SwiftUI/AppKit UI**, planned local OCR and direct distribution. Documents and file processing stay on the Mac.

**Current state: M1 development foundation.** The native app saves real folder configuration and pause state in a private local SQLite store with exclusive ownership. Folder setup starts disabled and never scans existing files. The separate sample rule/preview/history interface remains synthetic; watching, file actions, OCR, operational history and undo are not connected yet.

Build the development app with `make build`; see [development instructions and evidence boundaries](docs/DEVELOPMENT.md). `make test`, `make bridge-smoke`, `make presentation-smoke`, `make persistence-smoke`, `make check` and `make universal` verify the foundation.

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

Active change: [build-folder-master](openspec/changes/build-folder-master/proposal.md). Eight [capability specs](openspec/changes/build-folder-master/specs) define testable behavior; [implementation tasks](openspec/changes/build-folder-master/tasks.md) are checked only after their described behavior is implemented and verified. Current progress: 5/65 complete; M1 lifecycle/UX/platform gates remain open.

```sh
openspec status --change build-folder-master
openspec validate build-folder-master --strict
git status --short
git log --oneline
```

Planning is complete and the OpenSpec apply workflow is underway. Script isolation, native metadata preservation and target-OS runtime compatibility have explicit early feasibility gates. A plan passing validation is not proof of runtime behavior.

The separate [staged script proof](docs/SCRIPT_PROOF.md) passes basic XPC execution, but its strict IPC isolation gate fails. Product scripts remain unavailable; no unrestricted fallback is connected.

## Git tracking

Planning baseline is on `main`; implementation is on `feat/native-foundation`. No remote or publishing requested. Implementation uses focused branches, commits linked to task numbers and evidence updates in [PROGRESS.md](docs/PROGRESS.md). Generated builds, real documents, credentials and local tool state do not belong in commits. Installed `.agents` skills remain local workspace tooling.

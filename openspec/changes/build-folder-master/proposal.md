## Why

People repeatedly sort downloads, scans, and working documents by hand and need to understand and recover automated file changes. Folder Master will provide predictable, local-only folder automation on macOS 14 or later, with a Rust engine and a native interface.

## What Changes

- Add user-selected watched folders, ordered rules, and matching by name, extension, kind, size, dates, Finder tags, color labels, and document text.
- Add ordered move, copy, rename, tag/label, ZIP compression, ZIP extraction, Trash, permanent delete, and restricted local script actions.
- Add native PDF text extraction and on-device image/scanned-PDF OCR; never upload user documents or extracted text.
- Add a main management window, persistent menu bar controls, pause/resume, dry-run previews, manual runs, history, and conditional undo.
- Treat UI/UX as an early workstream, with native visual hierarchy, complete screen states, deliberate animations/transitions and reduced/off motion accessibility.
- Define explicit conflict handling, incomplete-file deferral, loop suppression, recovery, script isolation, and privacy boundaries before implementation.
- Track the design and subsequent implementation in local Git and an evidence-based OpenSpec task checklist. This change currently creates planning artifacts only.

## Capabilities

### New Capabilities

- `watched-folders`: Folder selection, scope, availability, events, reconciliation, and exclusions.
- `rule-engine`: Typed predicates, ordering, unknown values, time conditions, and versioned rules.
- `file-actions`: Ordered actions, target semantics, conflicts, archives, destructive operations, and scripts.
- `content-ocr`: Local text extraction, OCR, resource limits, and incomplete-content handling.
- `preview-execution`: Shared plans, dry-run isolation, preconditions, manual/automatic execution, and cancellation.
- `history-undo`: Durable operation history, recovery, inverse operations, and undo eligibility.
- `native-app`: Native window, rule editor, status menu, settings, UI/UX, animation/transition contracts, accessibility, and lifecycle.
- `local-runtime`: Privacy, script isolation, persistence, permissions, signing, and offline operation.

### Modified Capabilities

None. This is a greenfield workspace with no existing capability specifications or product source.

## Impact

Future implementation will add a Rust workspace, a SwiftUI/AppKit macOS app, small Apple-framework adapters, local SQLite storage, and a signed sandboxed script XPC service. Candidate dependencies and platform feasibility gates are documented in the technical design; no dependencies or product targets are installed in this proposal.

Product scope and acceptance criteria: [PRD](../../../docs/PRD.md) and [updated goal](../../../docs/GOAL.md). Interaction contracts: [user flows](../../../docs/USER_FLOWS.md), [user options](../../../docs/USER_OPTIONS.md), and [UI/UX and motion](../../../docs/UI_UX_DESIGN.md). Architecture: [technical design](design.md). Research: [source notes](../../../docs/RESEARCH.md).

# Native ordered action editor implementation plan

> **For agentic workers:** Execute inline against the existing OpenSpec plan; use test-first verification and a scoped review. The user has authorized continuing the full app goal.

**Goal:** Replace sample action strings with editable typed options for every requested action.

**Architecture:** Native form state remains separate from the durable Rust AST and execution authorization. Reuse native folder byte/bookmark handling and the existing motion policy. Stable UUIDs protect actions, arguments and asynchronous chooser completions from stale edits.

**Tech Stack:** SwiftUI/AppKit, Foundation, macOS 14; no new packages.

**Spec:** [Options section 4](../USER_OPTIONS.md), [file-actions](../../openspec/changes/build-folder-master/specs/file-actions/spec.md), tasks 1.11/1.12 and later 2.1/5.3.

## Constraints and review focus

- No file effects or script execution from editing, preview or chooser completion.
- At most 20 actions; terminal actions reject following actions and force Stop.
- Literal script argument rows preserve commas, spaces and empty arguments; configuration edits invalidate sample acknowledgements.
- Invalid destination/template/tag values block Save without changing the saved sample.
- Reorder/delete/duplicate and a chooser completing after selection changes must never edit a different action/rule.
- Guarded actions cannot enable while global capabilities/real approval mechanisms are unavailable. Native sample acknowledgements are not engine authorizations.

## Deliverable and verification

- [x] Write action-chain/value/identity/acknowledgement tests; observe failures against stubs.
- [x] Implement typed form model, structural template checks, selected local byte/bookmark adapter and stable argument operations.
- [x] Replace action rows with reusable native editor; integrate Save validation and independent duplicate identities.
- [x] Run linked Save regression smoke, full tests, static/OpenSpec checks and universal macOS-14 build.
- [x] Inspect native controls if UI tooling is available; explicitly record unavailable visual/accessibility/motion checks.
- [x] Review final diff, update progress evidence and commit the coherent slice. Do not check broader OpenSpec tasks until their entire acceptance is proven.

## Outcome

Implemented typed forms and guards; verified 24 Rust / 33 native passes with one existing physical-path skip, linked Save/session smoke, static/OpenSpec and universal min-14 build/signature. Six initial contracts failed against stubs; further regressions failed for inactive values, chooser ownership, executable mode and stale sessions before fixes. Native action UI/keyboard/VoiceOver/motion acceptance is **Not run**; offscreen capture was incomplete and excluded. No broader OpenSpec task was checked from this partial storyboard work.

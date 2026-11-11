# Folder Master — Product Requirements Document

Version 0.1 · 11 November 2026 · Status: proposed, ready for review after validation.

This document defines the product before implementation. TDD means **Technical Design Document** in this project; the [TDD](../openspec/changes/build-folder-master/design.md) includes verification strategy. No app has been implemented or benchmarked.

## 1. Product and intended outcome

Folder Master is a macOS 14+ menu bar utility that watches user-selected folders and applies understandable file organization rules. It pairs a Rust automation engine with a native SwiftUI/AppKit interface. A person should be able to add Downloads, preview a rule such as “PDFs containing invoice → rename, tag, move,” enable it, and later inspect or undo supported changes without a terminal.

### Confirmed choices

- macOS 14 or later; one or multiple watched folders.
- Rust engine with SwiftUI/AppKit UI, explicitly selected by the user.
- Direct download outside the Mac App Store, explicitly selected by the user.
- Documents, extracted text, OCR, rules, and history stay on the Mac; no document-upload service.
- PRD, TDD, user flows, user-visible options, OpenSpec, and Git tracking precede product implementation.
- UI, UX, animations and transitions are explicit first-class priorities, added by the user on 11 November; see the [updated tracked goal](GOAL.md) and [UI/UX design](UI_UX_DESIGN.md).

### Proposed defaults to review

Working name: Folder Master. English UI first; Unicode filenames and runtime-supported OCR languages. Native ZIP compression/extraction first; other archive formats deferred. Support Apple Silicon and Intel with a universal release. Scripts operate in an isolated offline workspace, rather than unrestricted terminal access. These are design decisions, not additional user-confirmed requests.

## 2. Users and motivating workflows

| User / moment | Desired rule | What creates trust |
| --- | --- | --- |
| Everyday Downloads cleanup | Extensions/kinds → destination folders | Preview exact destinations; handle duplicate names |
| Scanned bills and records | PDF/image OCR contains text → rename/tag/move | Works offline; incomplete recognition cannot trigger a negative-text rule |
| Project organization | Name/date/size/tags/label → ordered actions | Stable rule order; clear explanation of why it matched |
| Advanced local automation | Match → custom local script → publish outputs | Declared inputs/outputs; no network; timeout and visible failure |

## 3. Goals and non-goals

Goals: reliable unattended organization; clear controls over scope; predictable results; explainable history and conditional recovery; native accessibility; responsive UI during scans/OCR; no runtime dependence on internet connectivity.

Non-goals for 1.0: cloud sync/accounts, analytics, cloud OCR/AI, cross-platform UI, Mac App Store release, always-running system daemon, processing while the Mac sleeps, arbitrary system automation/AppleScript, unrestricted scripts, automatic updates, general-purpose document conversion, searchable-PDF generation, folders/packages as action targets, RAR/7z/TAR support, password-protected archives/PDF password storage, or guaranteed recovery of permanent deletion. Retain every requested action category within the concrete supported formats and boundaries below.

The utility runs while its per-user app process runs. Closing the main window leaves automation active; Quit stops it. Optional launch at login starts the app. No root privileges or automatic Full Disk Access request.

## 4. Functional requirements

IDs are stable acceptance and implementation references. Full option values/defaults live in [USER_OPTIONS.md](USER_OPTIONS.md); observable contracts live in the [OpenSpec capability specs](../openspec/changes/build-folder-master/specs).

| ID | Requirement | Release acceptance |
| --- | --- | --- |
| FR-01 | Add, enable, pause, edit, reconnect, and remove multiple watched folders | Folder chooser, persistent identity, restart and unavailable-volume handling; removal never removes user files |
| FR-02 | Configure recursion, hidden files, exclusions, and watcher mode | Non-recursive default; regular files only; packages, aliases and symlinks skipped; duplicates/overlapping watch scopes rejected |
| FR-03 | Match name, extension, kind, byte size, dates, Finder tags, color labels and content | Every family available in editor and independently demonstrated with match/non-match/unknown fixtures |
| FR-04 | Combine predicates with All / Any / None groups and ordered rules | Nested groups to depth 3; first matching rule wins by default; explicit continue evaluates the remaining rules against predicted current metadata |
| FR-05 | Create ordered move, copy, rename, tag/label, compress, uncompress, Trash, delete and script actions | All action categories implemented with options and restrictions in §6; partial failures visible |
| FR-06 | Extract text and run local OCR | UTF-8 text, PDF text, and OCR for supported local images/scanned PDF pages with explicit incompleteness |
| FR-07 | Preview without changing source or destination files | Explain matching, non-match, unknown, conflicts and actions; scripts never executed in preview; only local internal cache/history writes allowed |
| FR-08 | Run Now over existing files | Selected folder or all enabled folders; preview then run selected file chains; enabled rules only; manual run while paused explicitly confirmed |
| FR-09 | Control automation from menu bar | Global pause/resume, per-folder and per-rule toggles, run now, open window/history/settings, quit; error/paused/running state accessible without color |
| FR-10 | Retain durable local history and supported undo | Per-file and per-action status, explanations, timestamps, input/output paths, failure reason; inverse operations validated before undo |
| FR-11 | Recover after crashes and file-system interruptions | No blind replay of uncertain side effects; reconcile journal and actual files; show needs-review when ambiguous |
| FR-12 | Handle incomplete downloads, conflicts and output loops | Stabilization; exclude partial filenames; no replacement default; deduplicate app-generated events; no automatic script retry |
| FR-13 | Respect permissions and offline boundary | Local processing; restricted script service; no automatic cloud-file hydration; user-readable reconnect/permission errors |
| FR-14 | Manage rules without editing files | Draft/save/cancel, enable, duplicate, rename, reorder, delete, test draft, and save validation; new drafts disabled by default |
| FR-15 | Provide settings, lifecycle and local data controls | Login-item state, notification choice, OCR limits, retention, cache clearing, export history, reset confirmation; exact options in catalog |
| FR-16 | Design and verify UI, UX, animations and transitions from the first milestone | Screen/state matrix, native hierarchy, guided flows, deliberate motion, Reduce Motion/Off behavior and usability acceptance in UI_UX_DESIGN.md |

## 5. Matching and execution semantics

1. Rules belong to one watched folder. A rule contains name, enabled state, ordered position, condition tree, action chain, stop/continue behavior, revision, and explicit capabilities for dangerous actions. Duplicate rules within or into another folder as disabled drafts.
2. Conditions read a fresh file snapshot. Cheap metadata comes first; text/OCR is requested only when a condition cannot otherwise be resolved. Unavailable metadata/content or extraction failure yields **unknown**, never a fabricated empty value. Partial extraction can prove a positive literal substring; regex and negative text results require complete extraction. All/Any/None use three-valued logic; unknown rules perform no actions.
3. Default is first matching rule, ordered top to bottom. “Continue to next rule” uses the predicted post-action state of the current file. Copy and archive output stay secondary outputs; they do not replace the current file. Uncompress, Trash, delete and scripts are terminal. A move outside the original scope still completes the already-approved current rule's remaining actions (for example Move → Rename → Tag), then stops later rules.
4. Automatic mode starts only after the user enables folder/rules. Adding a folder does not run its existing files; initial indexing establishes a baseline. On resume/relaunch, reconcile changed/new files since that baseline. A newly enabled/saved rule does not act on unchanged historical files whose time conditions are already true; those require Run Now. Later false→true time-condition transitions while eligible can trigger automatically, including deadlines missed while paused/asleep.
5. Time-based predicates are reevaluated at their next relevant deadline, at least once a minute while awake. Launch/wake catches missed deadlines. Age means elapsed duration; Today/Yesterday use the configured local calendar and timezone captured per plan.
6. A stable file has unchanged size and content-modification time across two observations at least 2 seconds apart. Stability is a heuristic; revalidate before effects. Defer changing files up to 5 minutes, then show deferred; retry on a later event/manual run. Files named `.download`, `.crdownload`, `.part`, or `.partial` by extension are excluded by default.
7. File-level action failure stops that chain and its later rules. Other files continue. Earlier successful actions remain recorded and may be undone; multi-action chains and multi-file batches are not atomic transactions.
8. Default conflict policy is **Keep both** with a deterministic numbered suffix. Also support **Skip** and **Ask**. Ask creates a needs-review item during unattended execution. 1.0 does not overwrite existing files or merge directories. All conflicts are rechecked at commit time.
9. App-produced outputs do not automatically become fresh inputs anywhere in the watched set. Suppression is tied to operation IDs and output versions, not a permanent path blacklist; a later external change or explicit Run Now can process them. Undo output versions are suppressed in the same way.
10. Within one process, serialize effects affecting the same file or destination. Precondition failures invalidate stale preview rows; they never silently execute a newly expanded plan.
11. Preflight the whole chain before its first effect: unavailable guarded capabilities or unsafe multiply-linked metadata updates block the rule without preceding file changes. Revocation/pause after the chain begins can stop it at a later safe boundary with a partial result. Editing a saved revision does not replace an already-started pinned chain; disabling it still stops new steps.
12. Allow only local mounted volumes for watch roots, destinations, script/interpreter selection and exports; reject SMB/NFS/other remote volumes. A single engine owns each local data store before recovery or effects; a second app instance activates the existing instance or shows a non-writing state.

## 6. Actions, outputs and recovery promise

All targets are regular files. Relative destination templates stay inside a user-selected root; filenames cannot introduce traversal or separators. Secondary outputs are listed independently in preview and history. No automatic removal of originals after compression/extraction.

| Action | User chooses | Current-file behavior | Undo promise |
| --- | --- | --- | --- |
| Move | Destination root/subfolders, create missing subfolders, conflict policy | Current path becomes destination | Move back if output unchanged, original path free and volumes accessible |
| Copy | Destination and conflict policy | Original remains current | Remove unchanged created copy through a recovery-safe undo step |
| Rename | Template or find/replace; extension preservation | Current path renamed | Rename back if unchanged and old name free |
| Tags / label | Add/remove/replace tag names; optional set/clear Finder color label | Metadata changes on current file | Restore affected metadata if it still equals recorded post-action values |
| Compress | ZIP output root/name and conflict policy | Source stays current; archive secondary | Remove unchanged generated archive |
| Uncompress | ZIP input; chosen destination; named subfolder | Source remains; extraction terminal | Remove only verified unchanged extracted outputs; never pre-existing entries |
| Trash | No destination; terminal | File goes to system Trash | Restore while recorded Trash item exists, unchanged, and original path free |
| Permanently delete | Rule-specific opt-in; terminal | Unlink selected regular file | Unavailable; no secure-erase claim |
| Custom script | Local script/interpreter, literal argv, timeout, optional declared output root | Isolated staged input; terminal; source unchanged | No automatic undo for script execution or its published outputs in 1.0 |

Delete and scripts require global feature enablement plus per-rule acknowledgement before automatic execution. New duplicated/edited script content resets its acknowledgement. Manual delete batches also require a summary confirmation. Trash is the default offered destructive action. Unsupported undo is shown before execution, never implied by a global Undo button. No custom “undo script” in 1.0.

Scripts get a staged copy and metadata manifest. They can produce files in their isolated working directory; the app validates and publishes declared outputs under the selected destination. They cannot modify arbitrary original paths, access network/other apps, or request the host to run commands. Shell scripts via system zsh/sh and executable local files are in scope, subject to the signed helper compatibility gate. Python is available only if an explicitly selected local interpreter passes isolation checks; no runtime/model downloads. Unsupported scripts fail with a reason; they are never retried outside isolation.

## 7. Interface and flows

The main window uses a native three-column layout: folders/navigation, ordered rules, rule details. History and Settings have dedicated destinations. Inspector disclosure sections keep the initial editor simple; advanced values remain discoverable. Details, all buttons, default values, cancellation paths, empty/error states, and keyboard interactions are documented in [USER_FLOWS.md](USER_FLOWS.md) and [USER_OPTIONS.md](USER_OPTIONS.md).

Primary journeys: first launch → choose folder → create disabled draft → test → save and enable; file arrival → stabilize → match → plan → execute → history; Run Now → preview → select file rows → confirm → results; history → inspect → undo preview → confirm → result. Menu bar pause prevents new mutations; a current noninterruptible step completes before pausing.

Native quality: standard controls/SF Symbols, light/dark appearances, keyboard navigation, VoiceOver labels and action summaries, accessible status beyond color, resizable windows, Finder reveal, standard selection/context menus, and native file/folder panels. Main window targets a comfortable 1100×720 initial size and 820×560 minimum; collapsing sidebars/scrolling preserves all controls. Rule reordering also has keyboard Move Up/Down commands.

UI/UX is a design and implementation workstream from M1. [UI_UX_DESIGN.md](UI_UX_DESIGN.md) specifies visual hierarchy, screen/state coverage, progressive disclosure, feedback, focus continuity and a transition matrix. Motion follows system preferences, offers reduced/off settings, and never delays actions or suggests file success before engine confirmation.

## 8. Privacy and data policy

- No accounts, telemetry, remote crash reporter, runtime update check, cloud OCR, or network client in 1.0. Built-in operations must pass with outbound networking disabled.
- User data lives under local Application Support and local temporary/service containers with user-only access. Protect with normal macOS account security; recommend FileVault in help without claiming app-level encryption. Export happens only to the location the user chooses.
- Content is processed on demand. Optional extracted-text cache is off by default; in-memory bounded reuse is allowed. File paths and rule descriptions exist in local history; document text/snippets do not persist in history by default. “Show matched text” is transient and user-triggered. Script logs are capped and locally viewable, excluded from exports by default.
- Default history and undo metadata retention: 30 days or 100,000 action records, whichever bound is reached first. Cleanup invalidates undo explicitly; clearing history does not delete user originals/outputs. Protect unresolved operation journals from retention cleanup.
- Cloud-synced watched/destination folders may be uploaded by the user's sync software independently of Folder Master. Show this boundary when detected; default skips nonlocal placeholders and never requests hydration. The app cannot prohibit a user's existing third-party sync configuration.
- Distribution signing/notarization sends the built application artifact to Apple during release, never watched files. Runtime permission and Gatekeeper behavior belong to macOS, not the app's document processing.

## 9. Quality targets and release proof

These are targets to measure, not observed results. Baseline: M1-class Mac, 8 GB RAM, local APFS SSD, macOS 14, 10,000 files in one folder, two metadata rules; evaluate Intel separately. Content parsing and OCR have independent measured budgets.

| ID | Target | Evidence required |
| --- | --- | --- |
| NFR-01 | Offline processing; zero app/script document egress | Network-denied integration runs and script outbound/IPC escape attempts |
| NFR-02 | UI stays responsive; p95 common interactions under 100 ms during scan | Instruments/signposts and interaction samples on baseline |
| NFR-03 | Idle mean CPU below 1% over 10 minutes; idle RSS below 150 MiB | Release build measurement with idle watches; includes UI/core, excludes active helper work |
| NFR-04 | 10k-file metadata-only preview within 5 seconds after enumeration cache is warm | Reproducible fixture/benchmark, separately report cold scan and disk variance |
| NFR-05 | Eligible metadata-only arrival visible in history within 5 seconds p95 after becoming stable | At least 100 fixture arrivals, no OCR/network disk |
| NFR-06 | Bounded memory/queues; streaming large files; cancellation observable within 1 second at safe boundaries | Stress run, queue overflow test, large copy and OCR cancellation traces |
| NFR-07 | No source loss in supported fault cases; no overwrite; no mutation during preview | Conflict, disk-full, cross-volume, symlink-swap and injected crash tests |
| NFR-08 | Native macOS 14+ operation on arm64/x86_64 | Build/runtime matrix; signing/notarization tested on downloaded artifact before public release |
| NFR-09 | Every primary flow has designed loading/empty/error/success states; meaningful transitions honor system Reduce Motion and app Off | Screen-state review, keyboard/VoiceOver walkthrough, reduced/off motion recordings; timing/performance evidence per UI_UX_DESIGN.md |

Release is not accepted until every FR row and every supported action/matcher has evidence. OCR limits, unsupported files, protected PDFs, nonlocal placeholders and scripts that isolation blocks must produce explicit outcomes rather than silent success. “Exactly once” is not promised for arbitrary external effects or crash-ambiguous scripts.

## 10. Delivery milestones and definition of done

| Milestone | Reviewable deliverable | Gate |
| --- | --- | --- |
| P0 — design baseline | This PRD, TDD, options, flows, research, scenario specs and Git progress | Reviewed planning package; no product code yet |
| M1 — platform and experience foundation | Rust/native bridge, native screen/state prototype, core interaction/motion patterns, isolated-script/OCR/permissions proofs | Review UI/UX before scaling engine work; platform risks resolved without weakening offline contract |
| M2 — safe metadata automation | Watchers, typed rules, move/copy/rename/tag/Trash, shared preview, journal and undo | End-to-end preview→run→history→undo; failure injection |
| M3 — full requested action/content coverage | Date scheduling, text/OCR, ZIP, permanent delete, restricted scripts | Every requested family meets scenarios; no hidden downgrade to partial 1.0 |
| M4 — native management and lifecycle | Complete editor, status menu, history/settings, login integration, accessibility, verified animations/transitions | User-flow, visual-state, motion and accessibility checks |
| M5 — release candidate | Performance, stress/recovery evidence, universal signed artifact, local help | Privacy, permissions, macOS version matrix and distribution checks |

Detailed unchecked engineering tasks are in [tasks.md](../openspec/changes/build-folder-master/tasks.md). [PROGRESS.md](PROGRESS.md) records actual evidence. Stage completion is based on evidence, not just the existence of source files.

Definition of done for 1.0: complete requested capability coverage; passing relevant automated and manual checks; reviewed diff; no unacknowledged data-affecting behavior; signed artifact where credentials are supplied; help documents undo and offline limits. Missing signing credentials block public distribution, not local development. There is no estimate or shipping-date commitment yet.

## 11. Planning authority and change control

This PRD is product intent; user flows/options specialize interactions; OpenSpec scenarios are the testable behavior contract; the TDD defines implementation choices. Inconsistencies must be reconciled before implementation. New capabilities or changed user behavior require updating these affected artifacts in the same Git change. Archive the OpenSpec change only after implementation and verification; planning completion is not app completion.

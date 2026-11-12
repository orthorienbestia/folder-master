## 1. M1 — Build and platform feasibility

- [x] 1.1 Record actual Xcode/SDK/Rust versions, pin compatible tools/dependencies and initialize minimal Rust/native build targets; verify clean debug builds and deployment target 14.0 for every target.
- [x] 1.2 Implement the small versioned C bridge with ownership/error/cancel contracts; verify Swift→Rust→Swift roundtrip, malformed envelopes, buffer release, non-UTF-8 paths and contained panic handling.
- [ ] 1.3 Add native window/menu/settings lifecycle shell; verify menu persists after window close, Open focuses window and Quit shuts down safely.
- [x] 1.4 Build and locally sign the restricted script XPC proof; verify a staged zsh script can run and return only validated output without access to originals.
- [ ] 1.5 Exercise script child processes, network/IPC denial, interpreter compatibility and timeout termination on supported OS versions; record proof or a blocking design revision, never enable unrestricted fallback.
- [ ] 1.6 Prove folder identity/bookmark/TCC/local-placeholder handling on native adapters; verify moved roots, denied access and no intentional hydration.
- [x] 1.7 Prove native tags/label and byte/xattr/resource-fork/quarantine copy behavior on local and cross-volume fixtures; record preservation guarantees before committing action semantics.
- [x] 1.8 Prove local PDF text extraction, rasterization and Vision OCR with macOS-14 APIs; verify a synthetic scanned PDF/image with networking unavailable and record supported languages.
- [x] 1.9 Add schema-v1 SQLite migrations, journal/settings/rules storage and consistent backup; verify reopen, failed migration and newer-schema non-mutating behavior.
- [x] 1.10 Implement exclusive store ownership before recovery/writes; verify two app copies cannot mutate or recover the same journal and ownership recovers after process death.
- [ ] 1.11 Build the M1 native UI/UX storyboard with clearly labeled synthetic state providers; review folder/rule/preview/results/history flows, visual hierarchy and all core screen states before expanding engine implementation.
- [ ] 1.12 Implement shared presentation/motion tokens and policy in the storyboard; verify normal/reduced/off transitions, rapid interruption, keyboard/VoiceOver focus and truthful pending/success feedback.

## 2. M2 — Rules, discovery and shared planning

- [x] 2.1 Implement typed condition/action models and editor validation limits; verify roundtrip persistence, invalid field/operator pairs, empty/deep groups and terminal-action rejection.
- [x] 2.2 Implement name/extension/kind/size predicates; verify each operator, Unicode/case, unit boundaries, no extension and mismatched extension/kind fixtures.
- [x] 2.3 Implement date/tag/label predicates and All/Any/None logic; verify missing metadata, negative Unknown, calendar/elapsed semantics and truth tables.
- [x] 2.4 Implement template/regex/capture compilation; verify allowed tokens/date formats, invalid/ambiguous captures, traversal rejection and deterministic counters.
- [ ] 2.5 Implement folder enrollment, scope overlap/exclusion/package/symlink policy and baseline indexing; verify existing files remain untouched and regular-file scope is exact.
- [ ] 2.6 Integrate native watch events plus rescan/polling fallback; verify watches start before scan, root identity checks, event coalescing and missed-event reconciliation.
- [ ] 2.7 Implement stable-file deferral, burst coalescing, bounded queue/dirty fallback and output receipts; verify partial downloads, changing files, overflow and cross-watch loop suppression.
- [ ] 2.8 Implement the pure shared planner and current/secondary-file projection; verify first-match, Continue, moved-outside-scope and terminal/failure behavior against capability scenarios.
- [ ] 2.9 Implement dry-run mode and paginated explanations; verify no effect/script executor call, destination directory creation or user metadata mutation during preview.
- [ ] 2.10 Implement whole-chain preflight, selection/execution authorization, pinned active revisions, stale-precondition handling and confirmed paused one-time runs; verify changed unstarted rows, guarded-capability blocking and no implicit resume.

## 3. M2 — Journaled metadata actions and undo

- [ ] 3.1 Implement durable intent/result boundaries and file/destination serialization; inject storage failure and verify no unjournaled effect starts.
- [ ] 3.2 Implement same-volume move/rename with no-replace publication and case-only rename recovery; verify name conflicts and parent/symlink swaps cannot overwrite or escape scope.
- [ ] 3.3 Implement verified copy/cross-volume move with metadata preservation; verify content hash, changing source, disk-full and failed source-unlink partial outcomes on disposable volumes.
- [ ] 3.4 Implement tag/label effect and post-write roundtrip evidence; verify multiply-linked inputs are blocked, related Finder representation changes, permission failures and affected-value inverse preconditions.
- [ ] 3.5 Implement system Trash adapter and exact returned-location history; verify duplicate Trash names, unavailable Trash, no permanent-delete fallback and conditional restore.
- [ ] 3.6 Implement history/run queries, explanations, fingerprints and inverse descriptors; verify partial chains show actual retained effects and unsupported inverses are explicit.
- [ ] 3.7 Implement dependency-aware inverse planning/execution; verify move/rename/copy/tag/Trash undo, occupied original path, edited same-inode output and reverse order.
- [ ] 3.8 Implement startup journal reconciliation; inject crashes around copy publication, rename and unlink boundaries and verify no duplicate effects or invented success.
- [ ] 3.9 Implement pause/cancel/quit boundaries and storage-failure pause; verify queued steps stop, a current commit drains and partial outcomes remain inspectable.
- [ ] 3.10 Demonstrate the M2 vertical slice on fixtures: add folder→metadata rule→preview→Run Now→history→undo; record automated/native evidence and unresolved limits.

## 4. M3 — Content, temporal rules and advanced actions

- [ ] 4.1 Implement due-date scheduler and temporal truth receipts; verify already-true historical predicates wait for Run Now, later false-to-true transitions without events, wake catch-up, timezone/DST and no repeated unchanged work.
- [ ] 4.2 Implement bounded UTF-8/PDF text extraction; verify complete-empty, unsupported/protected/corrupt input and byte/page/text caps.
- [ ] 4.3 Implement local demand-driven OCR with per-page/frame processing and settings; verify scanned/mixed PDFs, force OCR, multipage TIFF, languages, timeout and cancellation.
- [ ] 4.4 Integrate partial-content tri-state matching and optional cache; verify negative text cannot match incomplete extraction, positive literal evidence, invalidation and clear-cache races.
- [ ] 4.5 Select/pin the ZIP implementation and prove supported metadata representation; deliver roundtrip fixtures documenting fields preserved and fields explicitly unsupported.
- [ ] 4.6 Implement streaming ZIP compression and output undo; verify source retention, archive validation, conflicts and unchanged-output inverse protection.
- [ ] 4.7 Implement validated ZIP staging/publication and manifest undo; verify traversal/links/devices/duplicates, CRC, expansion limits, pre-existing destination and foreign extraction contents.
- [ ] 4.8 Implement globally/per-rule guarded permanent delete and manual batch confirmation; verify disabled capability blocks unlink, exact selected entry only and no Undo claim.
- [ ] 4.9 Integrate approved script hashes, argv, staged inputs, limits, process-group cancel and explicit Test Script; verify changed script/interpreter/config invalidates approval and preview cannot invoke it.
- [ ] 4.10 Implement script output manifest validation/publication and cleanup/log limits; verify path/quota attacks, partial output publication, no automatic retry/undo and expired local staging removal.
- [ ] 4.11 Extend recovery/undo fault injection across ZIP, extraction, delete and scripts; verify uncertain irreversible effects remain Needs review without replay.
- [ ] 4.12 Demonstrate every requested matcher/action family on disposable fixtures and record its matching OpenSpec scenarios; do not mark full coverage from partial M2 behavior.

## 5. M4 — Complete native management and user flows

- [ ] 5.1 Implement folder list/detail setup, reconnect/remove and scope controls; manually verify cancel, unavailable volumes, overlap errors and settings-only removal.
- [ ] 5.2 Implement condition/group editor for all operator families with inline errors; verify save/cancel, keyboard focus and unknown-value explanations.
- [ ] 5.3 Implement ordered action editor, token picker, capability acknowledgements and terminal validation; verify every action option/default in USER_OPTIONS.md.
- [ ] 5.4 Implement rule duplicate/reorder/enable/revision management and dirty-draft prompts; verify no live edits alter saved automation and duplicate resets approvals.
- [ ] 5.5 Implement saved Preview, Test Draft and Run Now/results UI; verify filters, whole-file selection, stale rows, irreversible confirmation and one-time paused scope.
- [ ] 5.6 Implement complete status menu including folder/rule toggles and timed global pauses; verify persistent deadlines, accessibility status and no implicit enabling of disabled rules.
- [ ] 5.7 Implement searchable/filterable history, step inspector and inverse preview; verify partial/recovery states, undo barriers, reveal availability and explicit retry replanning.
- [ ] 5.8 Implement Settings, retention, cache clearing, JSON/CSV export and reset; verify exact ranges/defaults, selected export destination, no document text/log leakage and recovery-journal preservation.
- [ ] 5.9 Implement opt-in login launch and notification preferences with real OS status; verify denied/revoked approval and in-app errors still visible.
- [ ] 5.10 Implement packaged help/about/licenses and native appearance/accessibility polish; verify all USER_FLOWS.md journeys in light/dark, VoiceOver, keyboard-only and minimum window size.
- [ ] 5.11 Wire real engine state to the reviewed UI/motion components; record full screen/state coverage, interruptions, reduced/off modes, focus/scroll preservation and no false success under failed/delayed commands.
- [ ] 5.12 Conduct the first-time evaluator usability walkthrough from UI_UX_DESIGN.md; record confusion/fixes or explicit Not run if evaluator access is unavailable.

## 6. M5 — Release evidence and handoff

- [ ] 6.1 Execute the scenario coverage matrix across all eight specs; record passed/failed/not-run items with actual command/device/OS evidence in docs/PROGRESS.md.
- [ ] 6.2 Measure idle CPU/RSS, 10k metadata preview, arrival latency and UI interaction responsiveness under the PRD baseline; record observed values rather than assumed performance.
- [ ] 6.3 Stress burst events, large copy/OCR, concurrent external edits, storage exhaustion and volume disconnects; verify bounded queues/cache and conservative recovery.
- [ ] 6.4 Run offline/network-denied built-in processing and signed-script privacy/IPC probes; verify no document egress and preserve the test evidence.
- [ ] 6.5 Build arm64/x86_64 with deployment target 14.0 and exercise macOS 14/current-OS runtimes; report unavailable hardware/OS checks as Not run.
- [ ] 6.6 With provided release credentials, sign nested components, inspect entitlements, notarize/staple and validate a downloaded quarantined artifact including offline launch; missing credentials leave this task unchecked.
- [ ] 6.7 Measure small-transition timing/frame intervals and UI responsiveness with scans/large lists; record observed results against UI_UX_DESIGN.md targets, including reduced/off accessibility recordings.
- [ ] 6.8 Review final code/docs diff for scope and secrets, reconcile PRD/options/specs to observed behavior, and commit only verified coherent changes with updated task evidence.
- [ ] 6.9 After all required acceptance evidence exists, archive the OpenSpec change and verify generated main specs; update progress/release notes without implying pending checks passed.

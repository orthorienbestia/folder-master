# Development foundation

The app builds a native SwiftUI interface connected to a local Rust worker. Real folder configuration, typed rule revisions and pause state persist in SQLite; a separate **explicitly synthetic storyboard** demonstrates future preview/results/history screens. A native PDF/Vision adapter now passes local OCR fixtures. Watching, matching, file effects, OCR rule integration, durable operation execution and supported undo are not connected yet. Do not use this build to organize actual files.

## Toolchain

Verified development host on 11 November 2026: macOS 26.6.2 (25G83), arm64; Xcode 26.0.1 (17A400), macOS SDK 26.0; Swift 6.2, Swift language mode 5 for the app; XcodeGen 2.46.0; Rust/Cargo 1.89.0. Rust is pinned in rust-toolchain.toml; direct dependency versions and transitive resolution are pinned in Cargo.toml/Cargo.lock. No third-party Swift packages.

Every app/test target and Rust build sets macOS deployment target **14.0**. Compilation with a 14.0 minimum is not runtime proof on macOS 14. The Intel Rust target is installed for cross-compilation; Intel hardware/runtime validation remains a separate release gate.

VS Code uses the toolchain-matched rust-analyzer component listed in rust-toolchain.toml. If the editor was already open before installing components, run **rust-analyzer: Restart server**. On this host the newer bundled extension server could not analyze Rust 1.89 correctly; the matched `rust-analyzer 1.89.0` completed its diagnostic scan and VS Code's **Show RA Version** confirmed that binary. The installed extension 0.3.3113 sends the newer `inlayHints.implicitDrops.enable` string setting, which the older server warns about and ignores; this is a non-blocking editor configuration compatibility warning, not a Rust build failure. No global editor settings, extension downgrade or compiler upgrade was applied.

## Build and test

Run from the repository root:

```sh
# One-time prerequisite setup on a new development Mac (requires internet).
rustup target add --toolchain 1.89.0 aarch64-apple-darwin x86_64-apple-darwin
cargo fetch --locked

# Builds use cached, locked dependencies without network.
make build
make test
make bridge-smoke
make presentation-smoke
make persistence-smoke
make rule-persistence-smoke
make script-proof
make ocr-proof
make metadata-proof
make check
make universal
```

Install Xcode/Xcode command-line components and XcodeGen 2.46.0 first. XcodeGen's source spec is native/project.yml; the generated Xcode project and shared scheme are tracked. Regenerate after adding source files. The Rust build phase handles Xcode's temporary script location and the macOS system Bash. Build artifacts and test results stay under ignored build/ and target/.

Local build: build/DerivedData/Build/Products/Debug/Folder Master.app. Launch explicitly with Finder or `open 'build/DerivedData/Build/Products/Debug/Folder Master.app'`. Add Folder opens the native directory chooser and saves a disabled configuration without enumerating children. Display name, subfolder/hidden scope, exclusions and automatic/polling preferences are saved setup only. Explore Sample Interface opens the separate in-memory storyboard. Test Draft has no execution control; toolbar Preview offers fixed sample outcomes, selected-chain confirmation, pause/cancel, partial results, history inspection and sample undo. Sample folders have separate rule lists, Projects starts Off/empty, and Scans has an explicit simulated reconnect state. Unsaved navigation uses Save/Discard/Keep Editing; leaving/reentering sample mode retains saved session configuration, while quitting clears it. These screens do not evaluate your draft or perform file effects. See [storyboard evidence and missing acceptance](UI_STORYBOARD_EVIDENCE.md). Engine status explicitly reports automation unavailable.

The app owns `~/Library/Application Support/Folder Master` with user-only permissions. The Rust store retains a kernel `flock` lease on `store.lock` before opening the database; another instance receives a typed ownership error and cannot write folder or pause state. Retry can resume initialization after a canceled startup that already opened the store. The lease file is retained, and its descriptor closes after SQLite during shutdown; kernel ownership releases on process death. No user-file recovery/effects exist yet.

`make script-proof` builds a separate `ScriptProof` scheme and runs only generated synthetic cases. These proof targets are not dependencies of the product. `make script-isolation-proof` is a stricter acceptance gate and currently **fails** because Launch Services Mach lookup remains available to a script child, even though direct socket access is denied. See [exact evidence and coverage limits](SCRIPT_PROOF.md). Do not interpret the basic proof or the normal unit suite as full script isolation or expose it as a rule action. The proof uses ad-hoc signing; release client authentication and full quotas/runtime coverage are pending.

`make ocr-proof` builds the separate `OCRProof` scheme and runs a sandboxed, direct-network-denied synthetic content suite. The reusable adapter source is native/PlatformAdapters/DocumentText.swift; it takes Data/options, exposes structured coverage/issues and performs no source URL access or persistence. Dispatch it off the UI actor. Complete extraction refers to the selected source, not guaranteed recognition accuracy. Fast requires explicit supported languages; Accurate supports automatic detection. See [format, deadline, language and network evidence](OCR_PROOF.md). Rust request/response integration must respect the bridge's bounded envelopes rather than placing a multi-megabyte text result in one JSON message.

`make metadata-proof` compiles a standalone native harness targeting macOS 14 and creates a new disposable APFS image under build/. Host disk-image access is required. It tests tags/labels and native copies on the repository volume and the owned image, then detaches/removes that image. [METADATA_PROOF.md](METADATA_PROOF.md) records measured fields and limits: native tag/label coupling, exact non-quarantine xattr/resource-fork preservation, and system-rewritten quarantine bytes. It does not implement production copying or moving.

SQLite schema v1 includes folder configuration, settings, immutable rule revisions/heads, runs, operation journal, history, receipts and deadlines. Only folder/settings/internal rule snapshot operations are implemented; journal tables are provisioned for the subsequent durable-executor work. Migrations are transactional, newer schemas are inspected read-only and rejected, and backups use SQLite's online backup API to capture WAL contents before publishing a standalone no-replace file. The backup API is internal, with its user-facing export flow pending. SQLite 3 is bundled through pinned rusqlite 0.41.1 rather than relying on the installed system version.

Native enrollment validates directory/package/link/local-volume eligibility and stores an ordinary Foundation bookmark, not a TCC bypass. Reconnect, revoked access and cloud placeholder handling remain task 1.6/5.1 gates. Native filesystem URL helpers preserve raw bytes; this host's test volume rejects creating invalid UTF-8 names with EILSEQ, so physical enrollment of such a directory is explicitly skipped while byte-level URL/bridge roundtrips pass. Motion preferences still use AppStorage in this foundation and are disabled when workspace ownership is unavailable; full Settings persistence/export acceptance remains pending.

Local signing is ad hoc. Xcode reports that hardened runtime is disabled for this ad-hoc debug build. This does not satisfy the signed hardened/notarized release gate. The Cargo build phase's Xcode script sandbox is disabled so it can use the installed toolchain and build output directories; this is a build setting, not the runtime script-service isolation mechanism. The actual restricted script service is a separate pending task.

## Native Quit and isolated development data

Quit waits asynchronously for in-flight configuration commands, then prompts Save / Discard Changes / Cancel for a dirty real folder draft. Failed saves keep the app open with its draft and error. New workspace commands are disabled during preparation. The native Cancel and Save paths were exercised using a generated folder and isolated app database; this does not prove future file-effect shutdown or menu persistence after window close.

Debug builds alone accept `FOLDER_MASTER_TEST_DATA_ROOT` to isolate native UI checks from the normal Application Support store. It is a development harness input, not a product setting; Release ignores the environment variable. Each UI fixture must use a fresh private temporary directory, preserve its generated input bytes, and be cleaned up after the app exits.

## Bridge contract v1

C declarations: native/Bridge/FolderMasterEngine.h. Rust definitions: engine/src/bridge.rs. Native actor wrapper: native/FolderMaster/Bridge/EngineClient.swift. The caller owns a scalar engine handle, submits owned JSON bytes, polls correlated terminal events and releases returned buffers by allocation token. Input pointers must be readable for the declared length during the call; the engine copies data before returning. Pointers returned by poll remain valid until their allocation token is released. Never read them after release.

Supported foundation commands:

```json
{"version":1,"request_id":"unique-id","command":{"op":"status"}}
{"version":1,"request_id":"unique-id-2","command":{"op":"set_paused","paused":true}}
{"version":1,"request_id":"unique-id-3","command":{"op":"echo_path","path_bytes_base64":"L3RtcC//LnBkZg=="}}
{"version":1,"request_id":"unique-id-4","command":{"op":"open_store","path_bytes_base64":"L3RtcC9mb2xkZXItbWFzdGVyLWRhdGE="}}
{"version":1,"request_id":"unique-id-5","command":{"op":"list_folders","offset":0}}
```

echo_path is a non-I/O protocol check preserving raw path bytes, including non-UTF-8 filenames; it does not open a file. open_store requires an absolute path to a private local data directory; it creates schema v1 when new. list_folders pages ten records at a time with next_offset. add_folder, update_folder and remove_folder accept versioned configuration only, not file operations; see engine/src/worker.rs for typed fields. Stale revisions reject updates/removal. No file-effect commands are exposed. Maximum envelope is 1 MiB, outstanding requests per engine 64, engines 16, outstanding returned buffers 128. Backpressure returns a typed status instead of dropping terminal results.

Request IDs are unique among outstanding requests, retained until their event is polled. The native actor rejects already-canceled Tasks before dispatch and forwards later Task cancellation through the correlated ID. Cancellation can cancel queued work before it begins; a started/committed atomic foundation command returns TooLate. The native client still waits for the true terminal event, so cancel does not claim rollback. Successful cancellation produces one correlated canceled terminal event. Destroy cancels queued work, closes the channel and joins the worker; do it off the main actor. Returned buffers remain caller-owned until released even after an engine is destroyed. Releasing an allocation twice returns NotFound without freeing again.

| Status | Meaning |
| --- | --- |
| Ok / Empty | Accepted or event delivered / no event available |
| InvalidHandle / InvalidInput | Invalid or closed engine / malformed, oversized or unsupported protocol input |
| QueueFull / DuplicateRequest | Bounded capacity reached / request ID is already outstanding |
| NotFound / TooLate | Request/allocation no longer exists / command already started |
| Fatal | Internal failure; no completion/success claim |

Rust exports contain unwinding panics. A worker panic marks the worker failed and later work cannot apply. Allocation/OS process termination cannot be made recoverable by catch_unwind; filesystem crash recovery belongs to the pending durable journal implementation.

### Typed rule configuration

`engine/src/rules.rs` defines document schema version 1, independent of database/protocol version and each rule's revision. All eight condition and nine action families use field-specific types with strict unknown/duplicate-field rejection. Configuration validation enforces UUID identity, 200 extended-grapheme name limit, three group levels, 50 leaves, 1–20 actions, values/ranges, terminal ordering/Stop and unavailable guarded activation. Regex/template compilation is still pending; structural acceptance does not authorize execution. Locations preserve base64 byte paths/bookmarks; their shape is checked without opening the referenced files.

The existing envelope accepts these additional commands:

| `op` | Parameters | Completed payload |
| --- | --- | --- |
| `validate_rule` | `definition`: document object | `valid`, `issues` (first actionable issue, or empty) |
| `save_rule` | `folder_id`, `expected_revision`: null for create/current revision for update, `definition` | `rule`: folder, revision and definition |
| `get_rule` | `id`: rule UUID, `revision`: null for current/specific positive revision | `rule`: record or null |
| `list_rules` | `folder_id`, `offset`: nonnegative integer | `rules`: summaries, `folder_id`, `rule_count`, `next_offset` |

Validation works without an open store; save/get/list require ownership. Rule documents enter as raw JSON so duplicate fields cannot disappear into an intermediate map. The rule budget is 1 MiB minus 4 KiB for metadata/envelopes; list pages cap both 50 summaries and that byte budget. Each summary has UUID, revision, name, enabled, condition/action counts. Definitions are retrieved individually. See `engine/tests/support/rule_fixture.rs` for a complete schema-v1 rename definition and `typed_rule_bridge.rs` for requests.

Saves append immutable revisions in one transaction and compare the supplied current revision; stale saves, cross-folder updates, reused historical IDs and incompatible current documents are rejected without advancing the head. Folder removal drops current heads through the existing foreign-key cascade, retaining historical revisions. Creation order is stable across saves; explicit reordering is pending. Malformed Save returns `invalid_rule`, unsupported input schema returns `unsupported_rule_version`, and incompatible stored documents return `invalid_saved_rule`. Existing low-level `save_rule_snapshot` remains an opaque M1 storage primitive; new worker commands exclusively use typed APIs.

The real folder's Rules tab uses `LiveRuleModel`, `LiveRulesView` and `Shared/StoredRule.swift`. It retrieves summaries followed by the selected definition, maps the reviewed form controls to schema v1, then validates and saves through Rust. Success feedback follows the acknowledged revision; stale/failed commands retain the draft. Save retains form-only identities/acknowledgements after checking the returned configuration; these never become execution approvals. Folder/demo navigation and Quit protect both folder and rule drafts and asynchronously drain pending commands. A deliberate Reload Saved offers Save/Discard/Keep Editing when dirty. New rules start disabled, and saved enabled configuration cannot activate automation in this build.

The native adapter preserves exact UInt64 byte sizes with retained units, literal tag/argv values, byte paths/bookmarks and separate ZIP destination/filename capture sources. Label arrays compare as sets while duplicates remain invalid. Unknown or unrepresentable options fail to load for editing rather than disappearing on Save. Script/delete session acknowledgements reset on reload; executable/custom interpreter metadata is rechecked off the main actor without replacing stored references or executing content. Real script approval and runtime preflight remain pending. Sample location references cannot enter real persistence.

`make rule-persistence-smoke` exercises all condition operators/action families and alternate options through Swift→Rust→SQLite→Swift, crosses summary paging, checks exact maximum sizes, stale controller saves, deliberate reload, script metadata/session behavior and restart, and verifies generated source bytes remain untouched. This is configuration evidence, not preview or execution evidence.

## Evidence boundaries

Rust tests exercise worker/FFI contracts, persistence, immutable snapshots, migrations/rollback, consistent backup, private data boundaries and same/cross-process ownership including forced process death. Native XCTest covers motion/state plus native bookmark/path helpers. Bridge, presentation and persistence smoke targets compile/link real Swift and Rust; presentation covers dirty navigation, pending-save guards, initialization retry and Quit Save/Discard/Cancel including failed saves and pending-update draining, while persistence covers folder setup, revisions, reopen, pause, ownership and settings-only removal with original bytes retained. Queued post-submit cancellation through Swift is not deterministically exercised end to end yet; Rust unit tests exercise the queued cancel state. Native UI inspection covers the storyboard and real folder chooser/setup/cancel states; it does not prove file safety, OCR, script isolation, full accessibility or lifecycle behavior. See PROGRESS.md for actual outcomes and unfinished gates.

Both real and sample condition forms use `Shared/ConditionDraft.swift` and `ConditionTreeEditor.swift`: UUID-based recursive nodes, native value controls and structural limits. The real form serializes through StoredRule; neither form evaluates files. `PlatformAdapters/ContentSource.swift` is shared with the actual text adapter; keep the OCRProof target compiling when changing it. `make presentation-smoke` covers real rule navigation/Quit, sample Save isolation and name/condition guards, while XCTest covers exact size conversion, invalid groups/operators/ranges and stable node identity.

`Shared/ActionDraft.swift` and `ActionChainEditor.swift` provide typed native action form state. Location references carry byte paths/bookmarks and explicit sample labels; their metadata is not execution authorization. Draft session IDs and chooser request ownership guard delayed replies. Scripts/delete remain disabled; native template checks do not replace Rust regex/capture/template compilation or volume preflight. `make presentation-smoke` includes invalid-action Save and stale-session regressions; `ActionDraftTests` covers order, values, request ownership and disposable local-file selection. Rust uses pinned `unicode-segmentation` 1.12.0 for the rule-name limit; native OCR-target inputs are unchanged.

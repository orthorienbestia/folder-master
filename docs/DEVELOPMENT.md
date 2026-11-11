# Development foundation

The app currently builds and connects a native SwiftUI shell to a local Rust worker. Its folder/rule/preview/history screens are an **explicitly synthetic storyboard**. Real file watching/actions, OCR, journal storage and supported undo are not connected yet. Do not use this build to organize actual files.

## Toolchain

Verified development host on 11 November 2026: macOS 26.6.2 (25G83), arm64; Xcode 26.0.1 (17A400), macOS SDK 26.0; Swift 6.2, Swift language mode 5 for the app; XcodeGen 2.46.0; Rust/Cargo 1.89.0. Rust is pinned in rust-toolchain.toml; direct dependency versions and transitive resolution are pinned in Cargo.toml/Cargo.lock. No third-party Swift packages.

Every app/test target and Rust build sets macOS deployment target **14.0**. Compilation with a 14.0 minimum is not runtime proof on macOS 14. The Intel Rust target is installed for cross-compilation; Intel hardware/runtime validation remains a separate release gate.

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
make check
make universal
```

Install Xcode/Xcode command-line components and XcodeGen 2.46.0 first. XcodeGen's source spec is native/project.yml; the generated Xcode project and shared scheme are tracked. Regenerate after adding source files. The Rust build phase handles Xcode's temporary script location and the macOS system Bash. Build artifacts and test results stay under ignored build/ and target/.

Local build: build/DerivedData/Build/Products/Debug/Folder Master.app. Launch explicitly with Finder or `open 'build/DerivedData/Build/Products/Debug/Folder Master.app'`. Explore Interactive Preview loads in-memory synthetic examples; the banner and results disclose no files are read or changed. Settings exposes Follow System/Reduced/Off motion. Only the engine connection and pause acknowledgements are real; engine status explicitly reports automation unavailable.

Local signing is ad hoc. Xcode reports that hardened runtime is disabled for this ad-hoc debug build. This does not satisfy the signed hardened/notarized release gate. The Cargo build phase's Xcode script sandbox is disabled so it can use the installed toolchain and build output directories; this is a build setting, not the runtime script-service isolation mechanism. The actual restricted script service is a separate pending task.

## Bridge contract v1

C declarations: native/Bridge/FolderMasterEngine.h. Rust definitions: engine/src/bridge.rs. Native actor wrapper: native/FolderMaster/Bridge/EngineClient.swift. The caller owns a scalar engine handle, submits owned JSON bytes, polls correlated terminal events and releases returned buffers by allocation token. Input pointers must be readable for the declared length during the call; the engine copies data before returning. Pointers returned by poll remain valid until their allocation token is released. Never read them after release.

Supported foundation commands:

```json
{"version":1,"request_id":"unique-id","command":{"op":"status"}}
{"version":1,"request_id":"unique-id-2","command":{"op":"set_paused","paused":true}}
{"version":1,"request_id":"unique-id-3","command":{"op":"echo_path","path_bytes_base64":"L3RtcC//LnBkZg=="}}
```

echo_path is a non-I/O protocol check preserving raw path bytes, including non-UTF-8 filenames; it does not open a file. Delete/scripts/other unimplemented operations are rejected. Maximum envelope is 1 MiB, outstanding requests per engine 64, engines 16, outstanding returned buffers 128. Backpressure returns a typed status instead of dropping terminal results.

Request IDs are unique among outstanding requests, retained until their event is polled. The native actor rejects already-canceled Tasks before dispatch and forwards later Task cancellation through the correlated ID. Cancellation can cancel queued work before it begins; a started/committed atomic foundation command returns TooLate. The native client still waits for the true terminal event, so cancel does not claim rollback. Successful cancellation produces one correlated canceled terminal event. Destroy cancels queued work, closes the channel and joins the worker; do it off the main actor. Returned buffers remain caller-owned until released even after an engine is destroyed. Releasing an allocation twice returns NotFound without freeing again.

| Status | Meaning |
| --- | --- |
| Ok / Empty | Accepted or event delivered / no event available |
| InvalidHandle / InvalidInput | Invalid or closed engine / malformed, oversized or unsupported protocol input |
| QueueFull / DuplicateRequest | Bounded capacity reached / request ID is already outstanding |
| NotFound / TooLate | Request/allocation no longer exists / command already started |
| Fatal | Internal failure; no completion/success claim |

Rust exports contain unwinding panics. A worker panic marks the worker failed and later work cannot apply. Allocation/OS process termination cannot be made recoverable by catch_unwind; filesystem crash recovery belongs to the pending durable journal implementation.

## Evidence boundaries

Rust tests exercise the real worker/FFI plus cancellation and panic guards. Native XCTest covers motion restriction, ready-row selection and disabled independent rule duplication. The standalone Swift bridge smoke test compiles/links the real C ABI, exercises concurrent request correlation/raw path bytes, rejects pre-canceled mutations and closes the actor. A separate presentation smoke test checks dirty-New Save/Discard navigation and reselecting a rule without losing edits. Queued post-submit cancellation through Swift is not deterministically exercised end to end yet; Rust unit tests exercise the queued cancel state. Native UI inspection covers the visible storyboard flow; it does not prove file safety, OCR, script isolation, full accessibility or lifecycle behavior. See PROGRESS.md for actual outcomes and unfinished gates.

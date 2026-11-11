# Restricted script feasibility evidence

11 November 2026, macOS 26.6.2 arm64, Xcode 26.0.1. **Product scripts remain unavailable.** This is a separate test application and helper, not a rule action or a release implementation.

## Reproduce

```sh
make script-proof
make script-isolation-proof
```

The first target builds the `ScriptProof` scheme, locally signs the host/helper and runs fixed synthetic cases. The second is the stricter acceptance gate and currently exits nonzero. Both require a normal macOS user session with XPC and local signing available; they are separate from the Rust/native unit suite. No test sends data to an external server or asks another app to open a URL.

Sources: `tests/native/script-proof/`. XcodeGen definitions are in `native/project.yml`. Test products are under ignored `build/DerivedData`; the main FolderMaster target/scheme has no dependency on these products.

The proof host/helper/probe also compile as arm64+x86_64 with minimum macOS 14.0; nested signature verification passes. This does not establish Intel or macOS 14 runtime behavior.

## What passes

- The host pins the helper's designated signing requirement before activating NSXPCConnection. The helper has App Sandbox and no network client/server, Apple Events, user-selected-file or broad filesystem exception entitlement. Automatic debug entitlement injection is disabled for the helper.
- Approved synthetic script/input/metadata bytes are staged in a private per-job helper temporary directory. `/bin/zsh -f` receives literal argv and a scrubbed environment with per-job HOME/TMPDIR/cwd. The host exposes no filesystem, command or network callback.
- The script copies its staged input into an output file and preserves a literal argument containing shell metacharacters. Attempts to read/write a separate synthetic original fail; its bytes remain unchanged.
- Outputs are read via a retained directory descriptor, no-follow opens and regular-file/link-count/size/change checks; the host independently validates names, duplicates and aggregate result bytes. Symlink, hard-link and oversized output fixtures are rejected. Failed scripts return no publishable output.
- Malformed/future-version messages are rejected. Logs return at most 64 KiB. A one-second timeout stops the test script/process group in approximately 1.01 seconds on this host. Process group signaling occurs before its leader is reaped.

The initial staged-execution test failed against the `unavailable` runner stub, then passed after implementation. Negative cases exercise the real XPC service, not mocks.

## Isolation gate that fails

The same separately built `ScriptIsolationProbe` executable runs first from the unsandboxed host, then as a zsh child inside the helper. It has no sandbox entitlement of its own. It attempts a connection to a host-created loopback listener and looks up the Launch Services Mach port without sending a message to it.

| Exact binary context | Socket errno | Launch Services lookup return |
| --- | --- | --- |
| Unsandboxed host control | 0: connection succeeded | 0: lookup succeeded |
| Script child | 1: EPERM | 0: lookup succeeded |

This proves direct socket denial in that descendant and available Launch Services lookup. **A successful lookup alone does not prove a brokered upload or application launch.** It nevertheless contradicts the design's requirement to deny this IPC route. `--isolation` fails with `Unsafe Launch Services IPC remains available; do not enable product scripts`. The assertion remains in the gate; it is not ignored to obtain green tests.

The first probe reexecuted the sandbox-entitled service itself, which confounded the inheritance inference. Read-only review identified this weakness; it was replaced with the unentitled exact-binary control above.

## Authentication and coverage limits

Development uses ad-hoc signatures. The helper checks effective UID and the host bundle identifier; this does **not** authenticate against a same-user spoofed ad-hoc host. The product service needs a stable release Team-ID/host requirement and adversarial client tests before integration. The sandbox denied attempts to derive that host requirement by opening its containing app resources or inspecting the host process; filesystem exceptions were not granted to bypass those denials.

This proof deliberately uses small fixture bounds: 1 MiB input, 64 KiB script/metadata/logs, 32 flat output files, 4 MiB returned output bytes, and a 1–30 second timeout. They are not revisions to the product's option catalog. Disk/CPU/memory quotas while scripts run are not established by checking returned outputs. Nested outputs, custom interpreter compatibility, daemonized/escaped-session descendants, crash/disconnect cleanup, brokered IPC behavior and macOS 14/Intel runtimes remain unproven. A process group alone cannot account for a descendant that creates another session.

## Decision boundary

Task 1.4's basic staged-XPC proof can be assessed independently of task 1.5's full isolation gate. The current App Sandbox-only mechanism has **not** passed the required offline/IPC acceptance. Keep the product script capability off and preserve the no-egress contract while investigating a supported stronger mechanism. Do not replace the failing gate with identifier checks, an unrestricted host runner or an unreviewed deprecated sandbox profile. A mechanism that changes script/interpreter compatibility requires an explicit design revision; the public release gates remain open.

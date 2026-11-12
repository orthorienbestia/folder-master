# Mach bootstrap removal research

11 November 2026. **Exploratory candidate only; task 1.5 remains open and product scripts remain unavailable.** The existing `make script-isolation-proof` gate and its Launch Services assertion were not changed or rerun by this research. Its recorded failure remains the baseline in [SCRIPT_PROOF.md](SCRIPT_PROOF.md). No existing source, entitlement, Xcode project or product configuration was changed by this research.

## Finding

A native child can clear its kernel `TASK_BOOTSTRAP_PORT` with public Mach APIs before executing an interpreter. On this macOS 26.6.2 arm64 host, that state survives native and `/bin/zsh -f` exec, and the exact controlled probe then cannot look up Launch Services. Clearing only the userspace `bootstrap_port` variable is bypassable immediately. Retained old rights also remain usable. These observations justify a separate signed-helper experiment; they **do not establish** that arbitrary scripts, custom interpreters or descendants cannot recover broker access.

Keep App Sandbox as the filesystem/socket boundary. Bootstrap removal changes a task capability; it does not create an immutable policy denying every IPC mechanism. The inspected APIs/documentation provide no complete security guarantee for this composition.

## Installed SDK and primary-source checks

Checked Xcode 26.0.1, macOS SDK **26.0**, `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include`. Probe compilation succeeds for arm64+x86_64 with deployment minimum macOS 14.0; only arm64/current-OS execution was tested.

| API / alternative | Installed declaration and implication |
| --- | --- |
| `task_get_bootstrap_port`, `task_set_bootstrap_port` | `mach/task_special_ports.h:116–123`: macros over `task_get_special_port` / `task_set_special_port`, selector `TASK_BOOTSTRAP_PORT=4`. Public declarations in `mach/task.h:200–220`, without a macOS deprecation annotation. Changing the userspace global alone does not change this kernel slot. |
| `mach_ports_lookup`, `mach_ports_register` | Public Mach interfaces; registered rights are a separate inheritance channel. Clearing the bootstrap slot does not clear them. |
| `posix_spawnattr_setspecialport_np` | `spawn.h:160–161`, available macOS 10.5, not deprecated. Potential way to clear the child slot before its runtime initializes, without altering the long-lived service's namespace. Declaration checked; null-port spawn behavior was **not** executed in this research. |
| `bootstrap_parent`, `bootstrap_look_up` | `servers/bootstrap.h:69–93`, available macOS 10.4, not deprecated. Parent lookup requires a usable bootstrap capability. |
| `bootstrap_subset`, `bootstrap_create_server`, `bootstrap_unprivileged` | Same public header: deprecated in macOS 10.10, 10.10 and 10.5 respectively. A subset is not an acceptable assumption of total isolation. |
| `bootstrap_get_root`, `bootstrap_look_up_per_user` | Found in Apple's historical **private** `bootstrap_priv.h`, absent from the installed public bootstrap header. They take an existing bootstrap port; do not adopt them as the release mechanism. |
| Host special ports | Public header has `HOST_LAUNCHCTL_PORT=16` and `host_get_launchctl_port`; no `HOST_BOOTSTRAP_PORT` or `host_get_bootstrap_port` declaration was found in the inspected public headers. `host_get_special_port` takes `host_priv_t`, not ordinary `host_t`. Our ordinary `mach_host_self()` attempt returns `KERN_INVALID_ARGUMENT=4`. This is not proof about every host/IOKit route. |

Apple's XNU source distinguishes the bootstrap slot, registered rights and exception/host ports, and shows inheritance from the parent. Its setter replaces one slot and releases that slot's old reference; it does not revoke independent copies. User special-port getters also pass MAC policy checks. These implementation details support the cleanup questions, not a blanket escape-prevention guarantee. [XNU task IPC implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/ipc_tt.c)

The host-special-port getter requires a privileged-host object; the source separately exposes ordinary host access and I/O main access. Nulling the bootstrap slot is therefore not equivalent to removing all kernel capabilities. [XNU host implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/host.c), [host special port identifiers](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/host_special_ports.h), [Apple API reference](https://developer.apple.com/documentation/kernel/1589013-host_get_special_port)

Apple's historical launchd client/server sources show parent traversal, root lookup and per-user fallback using an existing namespace right. They also show parent namespaces can answer service lookups. They are historical reference, **not** a verified implementation of the installed macOS 26 libxpc. [Bootstrap client](https://github.com/apple-oss-distributions/launchd/blob/main/liblaunch/libbootstrap.c), [private declarations](https://github.com/apple-oss-distributions/launchd/blob/main/liblaunch/bootstrap_priv.h), [launchd server](https://github.com/apple-oss-distributions/launchd/blob/main/src/core.c)

Documentation procedure: Context7 CLI was run outside Codex's sandbox, three commands total: `library 'Darwin Mach bootstrap' ...` returned unrelated Mach/GNU Mach libraries; alternate `library 'Apple XNU' ...` resolved `/websites/developer_apple_kernel`; `docs` returned relevant task/host signatures but no isolation or recovery guarantee. Its setter snippet pointed at a broad `task_policy` page and was insufficient to establish behavior. Official web/API and Apple OSS sources above were then inspected. Some Apple API pages returned JavaScript shells or Markdown cache/access errors; the attempted archived `bootstrap.3` URL returned 404. Installed headers and controlled execution resolve declaration/behavior questions without inventing missing documentation. No third-party technical claims are relied on.

## Controlled own-process probe

Tracked source: [tests/native/script-bootstrap-research/probe.c](../tests/native/script-bootstrap-research/probe.c). Binaries and the observation log are local ignored artifacts under `build/script-bootstrap-research/`. Source SHA-256: `7d1468f4e5371c39919525e9baea8656f9c70ac7adb2a8cd26a2d9b3948f33b6`; captured log SHA-256: `2f5d00bbb70544b99c312ea2e683d4066e45201de014e5ddb3c70ffc9b82ae61`. A fresh clone can regenerate the log below; return codes can vary by OS/session.

The probe uses only its own task/host capabilities and read-only bootstrap queries. It deallocates returned rights. It never sends a message to the returned Launch Services port. One mode executes `/bin/launchctl print system/com.apple.logd`, discarding its service-state output; this queries launchd and does not launch or contact logd. No external or loopback traffic, user-file access, system changes or other-process signaling was used.

```sh
mkdir -p build/script-bootstrap-research
xcrun clang -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
  tests/native/script-bootstrap-research/probe.c -o build/script-bootstrap-research/probe
xcrun clang -Wall -Wextra -Werror -arch arm64 -arch x86_64 \
  -mmacosx-version-min=14.0 tests/native/script-bootstrap-research/probe.c \
  -o build/script-bootstrap-research/probe-universal
```

Run the following in a normal Terminal session **outside Codex's outer sandbox**, or via the host's approved outside-sandbox execution mechanism. Each mode is a separate process with a five-second supervisor deadline:

```sh
python3 - <<'PY'
import pathlib, subprocess
root = pathlib.Path('build/script-bootstrap-research')
control = subprocess.run(['/bin/launchctl', 'print', 'system/com.apple.logd'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                         text=True, timeout=5)
print('launchctl normal control exit=', control.returncode, control.stderr)
results = []
for mode in ['observe', 'global-only', 'saved-right', 'exec', 'shell',
             'exec-clean', 'shell-clean', 'launchctl', 'launchctl-clean']:
    try:
        p = subprocess.run([str(root / 'probe'), mode], capture_output=True,
                           text=True, timeout=5)
        result = f'MODE {mode} EXIT {p.returncode}\n' + p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        result = f'MODE {mode} TIMEOUT 5 seconds\n'
    results.append(result)
report = '\n'.join(results)
(root / 'observed-outside-codex-sandbox.txt').write_text(report)
print(report)
PY
```

`shell` executes zsh with literal argv and then execs the same probe; this is an exec chain, not a fork/session-escape test. Environment after exec contains only PATH and LANG.

The removal sequence is `task_set_bootstrap_port(mach_task_self(), MACH_PORT_NULL)` with checked success, plus `bootstrap_port=MACH_PORT_NULL`; the `*-clean` modes additionally check `mach_ports_register(mach_task_self(), NULL, 0)`. No App Sandbox policy is installed or changed by the probe.

| Mode / state | Observed outside Codex sandbox |
| --- | --- |
| Normal control | Global and kernel-slot Launch Services lookups succeed (`0`); parent capability also resolves it. |
| Global variable only cleared | Global lookup fails; retrieving the kernel slot still resolves Launch Services (`0`). **Reject this as enforcement.** |
| Kernel slot and global cleared, old right deliberately retained | Current-slot lookup fails; saved old right still resolves Launch Services (`0`). **Reject slot replacement alone as capability revocation.** |
| Kernel slot/global cleared, direct native exec or zsh exec chain | After exec both slots are null; lookups return `268435459` (`MACH_SEND_INVALID_DEST`). Parent lookup returns nonzero (`141` after exec); no parent right returned. |
| Registered rights | One valid registered right remains after removal and exec; its identity was not inferred or messaged. `*-clean` leaves zero valid registered rights before and after exec. |
| Host recovery query | `host_get_launchctl_port(mach_host_self(), ...)` returns `4`, no right, before and after removal. |
| Read-only launchctl query | Matching normal control exits `0`. After removal both variants exit `141` and report `Reentrancy avoided`; no successful recovery demonstrated. This is one command, not proof every libxpc/launchctl route fails. |

The first run inside Codex's sandbox had control lookup `1100` (`BOOTSTRAP_NOT_PRIVILEGED`), so it was excluded as a valid available-versus-denied isolation comparison. The outside run establishes the control. Neither run is the App Sandbox helper or the strict acceptance test.

Root verification repeated the five `observe`, `global-only`, `saved-right`, `exec-clean` and `shell-clean` controls outside Codex's sandbox on 12 November. All expected lookup distinctions and zero-valid-registered-right checks passed. The temporary verifier initially asserted a zero-length registered array; Mach returned three **null** slots, so the assertion was corrected to check zero valid rights rather than the array length. The source probe, reported property and strict script gate were unchanged. Its fresh log is ignored at `build/script-bootstrap-research/root-verification.txt`.

## Remaining bypass and compatibility questions

- **Retained capabilities:** account for registered ports, exception/debug/task-access ports, host/IOKit rights, XPC endpoints, already-open descriptors and library-cached send rights. Clearing a slot or registered array does not revoke copies already held elsewhere. This includes any send-right reference previously copied into a library global: assigning the variable to null does not itself deallocate that right. The probe’s `clean` suffix means registered-slot cleanup only, not an audited empty Mach port namespace. Use a fresh, minimal single-purpose child; do not alter the multithreaded XPC service's namespace or run unsafe post-fork library work inside it.
- **Recovery:** modern libxpc automatic fallback, independent XPC launch context and alternate launchctl operations are not covered by a complete public contract here. Test public API lookup and normal library paths in fresh native children. Never rewrite private libxpc globals as an enforcement strategy. Parent/root traversal must fail from every available namespace right, not just from `bootstrap_port`.
- **Same-user interaction:** namespace removal changes no UID or audit-session identity. Another same-user process may have capabilities the job lacks. Test attempts to acquire a controlled cooperating process's task/bootstrap rights and exchange synthetic capabilities; do not assume same-UID separation, ad-hoc identifier checks or hardened runtime alone solves this. Keep release authentication work from SCRIPT_PROOF separate.
- **Other IPC:** bootstrap removal does not itself deny Unix-domain sockets, shared memory, already-inherited channels or non-bootstrap broker paths. App Sandbox still needs to enforce the required boundaries. An empty namespace also does not enforce disk/CPU/memory limits, cleanup or descendant containment.
- **Compatibility:** zsh exec success does not cover `/bin/sh`, custom executable interpreters, dynamically loaded packages, Foundation/CF preferences, NSS/account lookup, GUI-dependent tools, spawning or daemonized descendants. Missing expected system services may cause failure. Preserve the native-script scope; report precise unsupported operations only after compatibility evidence and an explicit decision where scope changes.
- **Entitlements/distribution:** no new entitlement was required for the unsandboxed self-task calls, but whether the actual inherited helper sandbox permits the cleanup and retains every existing restriction is **not tested**. Do not add network, Mach-lookup, Apple Events, filesystem, debugging or private exceptions to make the experiment pass. Hardened runtime controls code injection and has compatibility exceptions; it is not a universal IPC deny policy. [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)

## Next exact experiment

Create a **separate opt-in proof variant**, preserving the current baseline gate. Run a small native child launcher from the existing signed sandboxed helper; make it fail closed on every cleanup error, clear the kernel bootstrap slot and registered rights, discard inherited capability channels, then exec an exact unentitled probe using literal argv/scrubbed environment. Compare the same binary in (1) unsandboxed control, (2) unchanged helper child and (3) helper→launcher→child. Capture sandbox retention (socket and synthetic-original denial), raw/public Mach lookup and parent recovery, registered ports, public XPC/library recovery, the read-only launchctl check and allowed staged output. Add native, sh/zsh, fork/exec and escaped-session descendants plus synthetic same-user capability-reacquisition controls; no messages to application brokers are needed for the initial denial test. Audit pre-exec startup/cached rights and the final child capability inventory. Evaluate macOS 14/current and Intel/arm64 separately.

If the variant regains broker lookup, reject that variant without weakening the baseline. If cleanup or needed interpreter behavior is incompatible, record that result and decide the mechanism explicitly. Even a passing lookup variant leaves authentication, quotas, all IPC routes, cleanup and release/runtime coverage open. No language/VM substitution or product enablement is authorized by this research.

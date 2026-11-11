# Native metadata and copy feasibility — M1 task 1.7

The standalone fixture harness demonstrates native tag/label interactions and copy preservation on two distinct local APFS volumes. It exposes no file effects in the app, engine or UI. There is intentionally no production metadata adapter or copy executor yet: the proof identifies platform behavior that the later journaled actions must accommodate.

## Reproduce

From the repository root:

```sh
make metadata-proof
# Equivalent direct runner: python3 tests/native/metadata-proof/run.py
```

The runner compiles `main.swift` with a macOS 14 deployment target, creates a new 64 MiB APFS disk image inside a unique `build/metadata-proof/run-*` directory, attaches only that image at its owned `mounted` path, runs the probes, detaches it and removes its directory. It does not enumerate or modify user folders. The Swift harness creates UUID-named fixture directories under its two supplied parents; only those directories are removed. It verifies Foundation `volumeIsLocal == true` and distinct `st_dev` values, rather than treating two folders on the same volume as cross-volume coverage. `statfs` records the actual filesystem type.

`hdiutil create/attach` needs normal host disk-image access. Codex's default sandbox returned `create failed - Device not configured`; the same owned-image operation succeeded through approved escalation. Run outside that sandbox using the approved mechanism. Do not attach an existing user image or select a user volume to work around an access failure. If attach/detach fails, the runner fails visibly and retains an image whose attachment state is uncertain; it does not force-detach volumes. Output is `build/metadata-proof/latest.json` (ignored generated evidence).

## Observed environment and checks

Executed on 2026-11-11, macOS 26.6.2 (25G83), arm64, Xcode 26.0.1 (17A400), macOS SDK 26.0. The repository volume and disposable image both reported `apfs` and native locality. The final curated run recorded distinct devices `16777232` and `16777257`. Device numbers are observations, not stable identifiers.

- **Passed:** 11 tag/label transitions on each volume, with fresh URL reads after each write and unchanged content hashes.
- **Passed:** 8 copy cases: Foundation `FileManager.copyItem(at:to:)` and Darwin `copyfile(COPYFILE_ALL | COPYFILE_EXCL)`, each within both volumes and across both directions.
- **Passed:** all 8 copies matched byte count/SHA-256, Finder tag/label readback, every non-quarantine xattr byte, permission mode `0640`, and modification time including `987654321` nanoseconds. Copied objects had separate identities. Each copy left its source unchanged in the measured fields.
- **Passed:** all 8 attempts to copy again onto an existing fixture destination failed; source and destination measured states stayed unchanged. This is a sequential existing-item check, not a race/publication proof.
- **Passed:** argument omission failed with an explicit usage error. Both arm64 and x86_64 versions compiled targeting macOS 14.0. Intel binary execution and macOS 14 runtime were **not run**.
- **Passed:** runner detached and removed its image. A separate `hdiutil info -plist` check found no remaining metadata-proof image attachment. The initial exploratory image was also detached and removed.

The curated [observed JSON](../tests/native/metadata-proof/observed-macos26-arm64.json) retains two actual runs, including different tag/color outcomes. The final curated run is timestamped `2026-11-11T09:28:12Z`. Integration reran the harness at `2026-11-11T09:28:12Z`: all 8 copies and 22 transitions passed after strengthening tag-replacement/removal assertions; owned-image cleanup and a separate attachment inventory both passed. The early run predates the runner's environment/cleanup annotations and the extra clear/restore-label probes; its values are retained to avoid hiding the observed variation.

## Tags and legacy labels interact

Native reads and writes use Foundation, not an invented on-disk tag encoding. Xattr bytes are compared opaquely for preservation only. These are measured examples, with English tag names on this machine:

| Native request | Observed related state |
| --- | --- |
| Set plain `FolderMasterPlain` tag on a fresh file | Label stayed `0` |
| Set label `6` while the plain tag exists | Plain tag name stayed; label became `6` |
| Clear that nonzero label | Plain tag name stayed; label became `0` |
| Replace tags with `FolderMasterReplacement` while label is `6` | Label became `0` |
| Set label `4` on a tagless file | Tag `Blue` appeared; label became `4` |
| Set tag name `Red` only | Label was `0` in the earlier run and `6` in the final run |
| Set tags and label `6` in a single dictionary request | Readback label was `0` in the earlier run and `6` in the final run |
| Remove all tags after a colored tag | Final run returned tagNames `nil` and label `0` |

The proof does not establish the cause of the across-run variation. Tag names cannot be treated as a fixed color mapping. A future action must snapshot both fields, use an explicit write order when order matters, then read back both fields and expose actual related changes. A combined write cannot promise independent requested results. The native API explicitly leaves multi-key write order undefined, may partially succeed, and may ignore unsupported keys without an error.

Foundation returned `nil` for tagNames on fresh/tag-cleared fixtures. That raw value remains `null` in the evidence. The SDK documents absent resource values as unavailable without a read error. This proof does **not** establish a universal rule that successful `nil` means an empty tag set; production matching must resolve absence/unavailability explicitly rather than fabricating an empty array.

## Copy preservation boundary

The source is a generated 262,144-byte binary file with a binary custom xattr, a 36-byte synthetic `com.apple.ResourceFork`, native tags, a legacy label/FinderInfo, and a synthetic quarantine record. Both native copy methods preserved the following tested metadata on both APFS volumes: `com.foldermaster.metadata-proof`, `com.apple.ResourceFork`, `com.apple.metadata:_kMDItemUserTags`, `com.apple.FinderInfo`, and the incidental `com.apple.provenance` attribute present during these runs. This is a measured field set, not a guarantee for every possible xattr or filesystem.

**Quarantine stayed present in every case, but was not always byte-identical.** Foundation same-volume copies retained the exact source record in these runs. Foundation cross-volume and all `copyfile.ALL_EXCL` cases returned a changed quarantine record. Example source:

```text
0081;6553f100;FolderMasterMetadataProof;00000000-0000-0000-0000-000000000001
```

The changed records began `0281`, had a new timestamp and an empty agent field, while retaining the fixture UUID. Exact source/destination values are in the JSON. The harness explicitly reports `allXattrsByteIdentical: false` for those cases; its acceptance assertion checks quarantine presence separately from exact non-quarantine xattr bytes. It neither strips quarantine nor overwrites the OS-generated record to force equality. No Gatekeeper execution or interpretation of undocumented flag bits was performed. A future executor must retain system quarantine and verify/report platform-managed metadata separately; it cannot claim all xattr bytes always stay identical.

For later actions, native copy is a feasible metadata-preserving building block on this tested APFS pair. This proof does not select a complete copy/move protocol. `copyfile` was called without MOVE/UNLINK/CLONE flags, and sources were never unlinked. The installed `copyfile(3)` manual documents that `COPYFILE_MOVE` can ignore source-removal failure; it must not substitute for the design's explicit verified-copy/source-revalidation/unlink protocol.

## API and compatibility evidence

Context7 CLI was run outside the default sandbox: official **Foundation** resolved to `/websites/developer_apple_foundation`, followed by focused docs queries for resource values and native copy. Primary API references: [tagNames](https://developer.apple.com/documentation/foundation/urlresourcevalues/tagnames), [URL resource keys](https://developer.apple.com/documentation/foundation/urlresourcekey), [setResourceValues](https://developer.apple.com/documentation/foundation/url/setresourcevalues(_:)), and [copyItem](https://developer.apple.com/documentation/foundation/filemanager/copyitem(at:to:)).

The installed Apple SDK `NSURL.h` declares `NSURLTagNamesKey` read-write since macOS 10.9 and `NSURL.setResourceValues` since 10.6. It documents undefined dictionary write order and partial-error unset-key reporting. The current Swift interface makes the `URLResourceValues.tagNames` **setter** available only on macOS 26+, even though its getter and the older resource-key API are available earlier. A first macOS 14-target compilation caught that incompatibility. The proof therefore uses `NSURL.setResourceValues([.tagNamesKey: …, .labelNumberKey: …])`; both architecture builds then compiled successfully for the macOS 14 target. This is compile compatibility evidence, not macOS 14 runtime coverage.

## Explicit limits

Not proved: full journaled copy/cross-volume move, source mutation handling, streaming/cancellation, disk full, ACLs/ownership/BSD flags/creation or access time preservation, arbitrary xattrs, unsupported filesystems (including ExFAT), external physical media, network/disconnected volumes, cloud-provider placeholders, permission/TCC failures, symlink/path-parent races, atomic/no-replace publication, crash recovery, user-interface Finder rendering, Gatekeeper behavior, ZIP preservation, or production undo. Multiply-linked metadata writes are deliberately outside this feasibility harness; the required blocker and recheck belong to task 3.4. The harness does not implement or prove those safety boundaries.

## Purpose

Execute ordered local file effects with explicit outputs, no silent replacement, and visible boundaries for irreversible or restricted actions.

## ADDED Requirements

### Requirement: Requested action coverage
The app SHALL support move, copy, rename, tag/color label, ZIP compression, ZIP extraction, system Trash, permanent delete and restricted local custom scripts for regular files. Each action SHALL expose the options and current-file/secondary-output semantics in the user option catalog. Terminal actions SHALL reject following actions.

#### Scenario: Compression retains source
- **WHEN** Compress succeeds
- **THEN** a ZIP is produced as a secondary output and the original file remains

#### Scenario: Invalid terminal chain
- **WHEN** a user appends an action after Trash, delete, uncompress or script
- **THEN** the editor rejects the invalid chain

### Requirement: No silent overwrite and root containment
All output publication SHALL honor Keep both, Skip or Ask conflicts, with Keep both default and no overwrite or directory merging. Targets SHALL stay within explicitly selected destination roots and SHALL resist symlink/path traversal and path-reuse races.

#### Scenario: Destination changes after preview
- **WHEN** another process creates the previewed destination before publication
- **THEN** the action rechecks conflict handling and does not replace that item

#### Scenario: Automatic Ask conflict
- **WHEN** unattended execution encounters a conflict configured as Ask
- **THEN** it creates a Needs review item and unrelated eligible files can continue

### Requirement: Verified copy and move
Copies and cross-volume moves SHALL stage, verify file bytes and required supported metadata before publication. Cross-volume moves SHALL remove the source only after verified destination publication and source revalidation. Uncertain/partial states SHALL be visible.

#### Scenario: Copy fails or source changes
- **WHEN** copy verification fails or the source changes before move source-removal
- **THEN** the app retains the source and records the actual failed or partial outcome

#### Scenario: Move source cannot be unlinked
- **WHEN** destination publication succeeded but source removal fails
- **THEN** history reports both surviving locations and does not label the move fully successful

### Requirement: Native metadata and Trash
The app SHALL preserve and verify supported metadata for built-in copy/move operations, apply tag/label changes through platform semantics, and record actual before/after values. Trash SHALL use system Trash and record the resulting item identity/location; failure SHALL NOT fall back to permanent deletion.

#### Scenario: Trash renames the item
- **WHEN** the system gives a trashed file a different name
- **THEN** history retains its actual Trash location for supported restoration

#### Scenario: Tag and label representation interacts
- **WHEN** a native tag/label update changes related representation
- **THEN** the actual metadata changes are recorded and explained rather than silently omitted

### Requirement: Safe ZIP extraction
Extraction SHALL retain its archive, validate entries, use a new output subfolder, never merge, and reject absolute/traversal paths, links, devices, encrypted/unsupported entries and duplicate equivalent names. Limits SHALL be 10,000 entries, 10 GiB expanded bytes, 1000:1 expansion ratio and twenty nested path components.

#### Scenario: Archive traversal
- **WHEN** a ZIP entry attempts to escape its output root
- **THEN** extraction fails before publishing any out-of-scope file

#### Scenario: Oversized archive
- **WHEN** an archive exceeds expansion limits during processing
- **THEN** extraction stops, retains the source and reports the limit reason without publishing a falsely complete output

### Requirement: Irreversible capability acknowledgement
Permanent delete and scripts SHALL require separate global enablement and valid per-rule acknowledgement. Delete SHALL unlink only the selected regular directory entry and expose no Undo promise. Manual delete batches SHALL require explicit confirmation.

#### Scenario: Capability disabled
- **WHEN** a saved rule includes deletion or scripts but its global capability is off
- **THEN** the whole chain is blocked before preceding actions can change files

#### Scenario: Shared hard-link metadata
- **WHEN** a chain would tag or label a file with multiple hard links
- **THEN** preflight blocks that chain because the change could affect an unselected path

### Requirement: Restricted script effects
Scripts SHALL execute only on staged local inputs through the offline isolation boundary, with literal argv, time/resource limits, approval hashes and declared output publication. Scripts SHALL be terminal, never run during preview, never receive unrestricted host callbacks, and have no automatic undo or retry after ambiguous execution.

#### Scenario: Script changed after approval
- **WHEN** script/interpreter bytes or approved invocation configuration changes
- **THEN** execution is blocked until the new configuration is explicitly acknowledged

#### Scenario: Script requests network or original writes
- **WHEN** a script attempts network access or modifying an original outside its stage
- **THEN** isolation denies that access and no unrestricted fallback runs

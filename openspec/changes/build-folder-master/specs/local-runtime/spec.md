## Purpose

Keep document automation local, persist user configuration safely and preserve explicit platform, permission and distribution boundaries.

## ADDED Requirements

### Requirement: No document egress
The app SHALL process files/OCR locally without accounts, telemetry, runtime update checks, remote crash reporting, cloud inference or file upload. Built-in processing SHALL work without outbound network. External sync software and explicit browser help navigation SHALL be disclosed separately.

#### Scenario: No internet connection
- **WHEN** outbound networking is unavailable
- **THEN** built-in matching, OCR and actions continue for supported local files without contacting a remote service

#### Scenario: Cloud-synced destination
- **WHEN** the app identifies a selected destination as externally synced
- **THEN** it explains that other sync software may upload files and does not claim to control that software

### Requirement: Enforced offline script boundary
Custom scripts SHALL run under an independently enforced sandbox without network/automation powers, on staged inputs with bounded outputs and no host command/filesystem proxy. Descendants SHALL retain restrictions. If isolation cannot be established, scripts SHALL remain unavailable rather than falling back to unrestricted execution.

#### Scenario: Network attempt by child
- **WHEN** a script launches a child that attempts outbound networking
- **THEN** access is denied within the same enforced boundary

#### Scenario: Isolation unavailable
- **WHEN** the installed platform cannot safely run a requested interpreter
- **THEN** the action fails with an explicit reason and does not execute in the host process

### Requirement: Selected-root and OS permission boundaries
File operations SHALL remain scoped to chosen roots and OS-granted access without root privileges or automatic broad-access permission requests. Bookmarks/identities SHALL not be represented as bypassing macOS privacy controls.

All selected watch roots, destinations, scripts/interpreters and export locations SHALL be on local mounted volumes. Remote mounted filesystems SHALL be rejected to preserve the on-Mac processing/storage boundary.

#### Scenario: Protected folder denied
- **WHEN** macOS denies access to a selected folder
- **THEN** the app explains how to resolve access or choose another folder and does not force access

#### Scenario: Mounted network destination
- **WHEN** the user selects an SMB/NFS or other remote mounted destination
- **THEN** the app rejects it rather than sending file bytes to remote storage

### Requirement: Exclusive engine ownership
Only one writing engine SHALL own an app data store at a time, including before startup recovery. Other app instances SHALL activate the existing owner or present a non-writing state, and SHALL NOT reconcile the owner's live operations.

#### Scenario: Second app copy starts
- **WHEN** another app copy/version starts while the same data store is owned
- **THEN** it does not execute rules, write configuration or recover the first instance's active journal

### Requirement: Local persistence and schema safety
Rules/settings/history/cache SHALL remain in app-owned local storage with user-only access. Unknown/newer or failed schemas SHALL stop automation without modifying incompatible data. Backup/restore SHALL preserve database consistency and unresolved operation evidence.

#### Scenario: Newer database version
- **WHEN** an older app encounters a database schema it cannot read safely
- **THEN** it starts a non-mutating recovery/help state rather than downgrading data

### Requirement: Bounded private data handling
Document text SHALL be transient unless local cache is enabled, history SHALL exclude it by default, logs/staging SHALL be bounded, and exports SHALL require a chosen local save location with disclosure of included paths/logs.

#### Scenario: History export
- **WHEN** the user exports filtered history
- **THEN** the chosen local file contains disclosed fields and script logs are excluded unless explicitly selected

### Requirement: Direct macOS distribution readiness
Public release SHALL support the declared macOS/architecture targets, use signed hardened app/helper components and a validated notarized direct-distribution artifact. Missing release credentials or unavailable runtime checks SHALL remain explicit incomplete release gates.

#### Scenario: Local build without Developer ID
- **WHEN** development succeeds but public signing/notarization is not available
- **THEN** progress reports local-build evidence and does not claim a distribution-ready release

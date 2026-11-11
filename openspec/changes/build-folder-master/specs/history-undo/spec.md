## Purpose

Retain trustworthy local evidence of filesystem effects and offer conservative, dependency-aware undo for actions that can be safely compensated.

## ADDED Requirements

### Requirement: Durable history and recovery evidence
Every mutation SHALL have durable intent and recorded observed outcome. History SHALL show run/trigger, rule revision, file/action paths, timestamps, status, failure/partial details and undo eligibility. Unresolved recovery journals SHALL survive history clearing and retention.

#### Scenario: Cannot persist intent
- **WHEN** operation-intent persistence fails
- **THEN** no new unjournaled filesystem mutation starts and automation reports the storage problem

### Requirement: Conservative crash recovery
On restart, the app SHALL reconcile interrupted intents with actual files before resuming automation. It SHALL distinguish known committed/failed states from ambiguous states, and SHALL NOT blindly replay deletion or scripts with uncertain effects.

#### Scenario: Crash after output publication
- **WHEN** the app restarts with an applying operation whose output may already exist
- **THEN** it inspects recorded identities/versions and recovers or requests review without duplicate publication

#### Scenario: Script outcome unknown
- **WHEN** a script was interrupted after execution may have begun
- **THEN** the app records Needs review and does not automatically rerun it

### Requirement: Explicit conditional inverse support
Undo SHALL support safe move/rename/Trash restoration, removal of unchanged app-created copy/ZIP/extraction outputs, and restoration of affected tag/label values. Delete and scripts SHALL have no automatic inverse. Undo SHALL require unchanged verified objects, available original paths and retained evidence.

#### Scenario: User edited output in place
- **WHEN** an output's inode is unchanged but its content changed since the action
- **THEN** the app blocks an inverse that would discard the edit

#### Scenario: Trash was emptied
- **WHEN** the recorded Trash item is no longer present
- **THEN** undo is unavailable with a specific explanation

### Requirement: Dependency-aware undo preview
Undo SHALL preview inverse operations, validate dependencies and apply eligible steps in reverse order. Non-reversible steps SHALL be barriers to a full-chain Undo promise. Undo SHALL never force overwrite or remove pre-existing/foreign files.

#### Scenario: Extraction directory gained foreign files
- **WHEN** an extraction output contains files absent from the recorded output manifest
- **THEN** whole-chain undo is blocked by default and foreign files remain

#### Scenario: Irreversible step in chain
- **WHEN** a chain contains a script or permanent delete
- **THEN** the app explains the barrier and offers only independently safe reversible suffixes if any

### Requirement: Audited undo and retention
Undo SHALL append history, retain original action evidence, and suppress automatic reprocessing of its own outputs. Completed history SHALL default to thirty days/100,000 action records with configurable bounded retention. Cleanup/clear SHALL explain lost undo and SHALL NOT delete user originals/outputs.

#### Scenario: Undo move
- **WHEN** an eligible move is undone
- **THEN** restoration is journaled as a new operation and its unchanged output does not immediately trigger the same rule again

#### Scenario: Clear completed history
- **WHEN** the user confirms clearing completed records
- **THEN** the app removes completed history/undo metadata while preserving user files and unresolved recovery journals

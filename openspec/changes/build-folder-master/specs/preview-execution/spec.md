## Purpose

Give users an accurate, non-mutating preview and controlled execution over existing or newly eligible files with clear cancellation and stale-plan behavior.

## ADDED Requirements

### Requirement: Shared explainable preview
Saved-rule preview and execution SHALL use the same planning semantics and expose matching explanations, ordered effects, destinations, secondary outputs, conflicts, reversibility and unknowns. Test Draft SHALL provide no Apply action.

#### Scenario: Same input plan
- **WHEN** unchanged files, destinations, settings and rule revisions are previewed and then executed
- **THEN** execution follows the same planned action chain and output semantics

### Requirement: Dry-run side-effect isolation
Preview SHALL NOT perform action effects, execute scripts, create destination directories, move/copy/rename/tag/compress/extract/trash/delete user files, or intentionally modify their metadata. Local internal caches/history and normal OS read bookkeeping SHALL be the disclosed exceptions.

#### Scenario: Script in preview
- **WHEN** a matching rule ends with a script
- **THEN** preview shows Would execute with unknown effects and never starts the script

#### Scenario: Missing destination subdirectory
- **WHEN** a previewed move would need a new subdirectory
- **THEN** preview can describe it without creating it

### Requirement: Explicit manual-run scope
Run Now SHALL operate on selected folder or all enabled folders using enabled saved rules, preview first, and allow selection of complete ready file chains. A paused-scope run SHALL require explicit one-time override and SHALL NOT resume automation.

#### Scenario: Manual run while paused
- **WHEN** the user confirms Run once while paused
- **THEN** only the selected manual work runs and global/folder pause states remain unchanged

### Requirement: Preconditions and stale plans
Execution SHALL validate the current rule revision and whole-chain authorization before the first effect, then revalidate expected evolving-file state, authorized roots, live enable/capability state and destinations before each step. Already-started chains SHALL retain their pinned revision across rule content edits, but SHALL stop at safe boundaries for pause/disable/revoked capabilities. Changed or unsafe unstarted rows SHALL require refresh/review rather than silently expanding/replacing the approved plan.

#### Scenario: File edited after preview
- **WHEN** a selected file changes after preview
- **THEN** its stale chain is blocked with Needs refresh and no guessed action is applied

#### Scenario: Save new revision during active chain
- **WHEN** the user saves changed rule content after a file chain began
- **THEN** that chain keeps its pinned revision and unstarted affected work replans

### Requirement: Partial execution and cancellation
An action failure SHALL stop its chain and later rules for that file while allowing independent files to continue. Pause/cancel SHALL stop new effects at safe boundaries and SHALL disclose retained completed effects without claiming rollback.

#### Scenario: Third action fails
- **WHEN** two actions succeed and a third fails
- **THEN** history shows the first two effects and a partially completed chain with supported undo eligibility

#### Scenario: Cancel during publication
- **WHEN** cancel arrives during a noninterruptible commit step
- **THEN** that step reaches a safe result and no subsequent step starts

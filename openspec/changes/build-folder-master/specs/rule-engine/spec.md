## Purpose

Provide user-editable, ordered and explainable file rules with precise matching behavior and safe treatment of unavailable metadata or text.

## ADDED Requirements

### Requirement: Complete typed condition catalog
The app SHALL offer name, extension, kind, size, date, Finder tags, Finder color label and text-content predicates with the operators, defaults and value validation in the user option catalog. It SHALL distinguish missing/unavailable metadata from successfully read empty values.

#### Scenario: Extension and kind differ
- **WHEN** the user chooses an extension predicate or a kind predicate
- **THEN** the app evaluates the final extension or platform content-type category respectively and explains the selected basis

#### Scenario: Metadata read failure
- **WHEN** a label, date or tag field cannot be read
- **THEN** its predicate result is Unknown rather than an empty value

### Requirement: Three-valued groups
Rules SHALL combine predicates through All, Any and None groups to depth three with no empty groups and at most fifty leaf predicates. All/Any/None SHALL preserve Unknown under the documented truth tables; a rule whose overall result is Unknown SHALL perform no actions.

#### Scenario: Negative unavailable content
- **WHEN** a rule tests that text does not contain a phrase but text cannot be extracted completely
- **THEN** the absence predicate is Unknown and cannot trigger actions

#### Scenario: Decisive group branch
- **WHEN** an Any group contains a known true predicate and an unknown predicate
- **THEN** the group is true without requiring the unknown branch to become known

### Requirement: Ordered rule and current-file semantics
Enabled rules SHALL run in saved order, default to stopping after a match, and offer explicit Continue. Continue SHALL evaluate later rules against projected current-file state. Copy/ZIP outputs SHALL remain secondary; terminal actions SHALL stop the chain. A move outside original scope SHALL complete that rule's remaining approved actions and then stop later rules. Failed action chains SHALL stop later rules for that file.

#### Scenario: Rename then continue
- **WHEN** a matched rule renames the current file and continues
- **THEN** later name predicates use the renamed current file

#### Scenario: Copy then continue
- **WHEN** a rule copies a file and continues
- **THEN** later rules use the original current file rather than the copy

#### Scenario: Move outside scope with remaining actions
- **WHEN** a matched rule moves a file outside its watch scope and then renames/tags it
- **THEN** those already-approved actions complete at the authorized destination and later rules do not run

#### Scenario: Unknown then independent match
- **WHEN** an earlier rule is Unknown and a later independent enabled rule matches
- **THEN** only the later matching rule's authorized actions can run

### Requirement: Revisioned editing and enablement
The app SHALL support disabled drafts, save/cancel, test draft, duplicate, reorder, enable/disable and delete configuration. Save SHALL validate conditions/actions and create an immutable revision. Active chains SHALL retain their pinned revision; pending work and previews SHALL honor revision changes. Duplicate SHALL reset guarded-action approvals.

#### Scenario: Draft is edited
- **WHEN** the user changes an unsaved rule
- **THEN** saved automation behavior remains unchanged until a valid save occurs

#### Scenario: Reorder while preview open
- **WHEN** rule priority changes after preview
- **THEN** affected preview rows require refresh before execution

### Requirement: Time and template determinism
Plans SHALL capture clock/timezone for absolute/calendar dates, use elapsed durations for age, and assign template/counter results deterministically. Invalid regex, units, dates, unsupported captures or escaping templates SHALL be rejected with field-level errors.

#### Scenario: Missing rename date token
- **WHEN** a template requires an unavailable created date
- **THEN** the action is not executed with an invented date

#### Scenario: Relative age persists true
- **WHEN** a file remains older than a threshold across repeated scheduler ticks
- **THEN** unchanged work is not repeated every tick solely because the condition remains true

#### Scenario: Already-old historical file
- **WHEN** a rule is enabled and an unchanged historical file already satisfies its age condition
- **THEN** it is baselined without actions and requires Run Now, while later false-to-true transitions remain automatically eligible

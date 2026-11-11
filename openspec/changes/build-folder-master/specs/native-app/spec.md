## Purpose

Expose file automation through a native macOS management window and persistent menu bar controls with accessible, understandable state transitions.

## ADDED Requirements

### Requirement: Native management surfaces
The app SHALL support macOS 14+, provide a main window with folders, ordered rules and details, and dedicated history/settings surfaces. It SHALL use native controls/panels, light/dark appearance, keyboard navigation and VoiceOver-readable labels/status. All options in the catalog SHALL have discoverable controls and validation.

#### Scenario: Keyboard-only editing
- **WHEN** a user creates and reorders a rule using keyboard navigation
- **THEN** every required field and Move Up/Down action is accessible without drag gestures

### Requirement: Persistent menu bar control
The menu SHALL expose global pause/resume, timed pause, per-folder and per-rule saved enable states, preview/run, window/history/settings, eligible undo preview and Quit. Status SHALL be understandable without relying on color.

#### Scenario: Global resume with disabled rule
- **WHEN** global automation resumes
- **THEN** individually disabled rules remain disabled

### Requirement: Draft and empty/error states
The UI SHALL distinguish drafts from saved revisions, prompt Save/Discard/Keep Editing before losing unsaved edits, and provide actionable empty, unavailable, unknown, conflict and permission states.

#### Scenario: Navigate away from dirty draft
- **WHEN** the user selects another folder while a draft has changes
- **THEN** the app offers Save, Discard or Keep Editing and does not silently commit or discard it

### Requirement: App lifecycle and login
Closing the main window SHALL leave the app/menu automation running; Quit SHALL stop it at a safe boundary. Launch at login SHALL be opt-in and show the actual system approval status. The app SHALL NOT claim operation while asleep/logged out.

#### Scenario: Close window
- **WHEN** the management window closes while automation is enabled
- **THEN** the menu bar remains and the app continues eligible work

#### Scenario: Login approval denied
- **WHEN** macOS has not approved login launch
- **THEN** Settings displays the system state rather than falsely claiming login launch is active

### Requirement: Data management and help
The UI SHALL expose local history export, bounded retention, cache clearing, reset confirmation and packaged local help. Reset SHALL stop automation and SHALL NOT remove watched/destination files or unresolved recovery journals.

#### Scenario: Reset data
- **WHEN** the user confirms settings/history reset
- **THEN** only the chosen app-owned completed data/configuration is cleared and user files remain

### Requirement: Explicit UI and UX state coverage
The app SHALL implement the screen/state, hierarchy, progressive disclosure, focus and feedback contracts in UI_UX_DESIGN.md. Each primary flow SHALL expose understandable initial/loading/empty/error/success states, preserve user context during background updates and distinguish simulation/pending state from real engine outcomes.

#### Scenario: Background results arrive
- **WHEN** a user is inspecting a selected preview/history row while more rows arrive
- **THEN** selection, scroll anchor and keyboard focus remain stable

#### Scenario: Engine failure during pending command
- **WHEN** an operation fails while the UI is showing pending feedback
- **THEN** the UI presents the actual failure/partial state and never transitions to successful effects merely because an animation completed

### Requirement: Purposeful accessible motion
App-authored animations/transitions SHALL follow the documented motion matrix, be interruptible, never delay command/cancel semantics and respect system Reduce Motion plus app Follow System/Reduced/Off settings. Reduced SHALL remove displacement/scale/spring motion and limit opacity to one hundred milliseconds; Off SHALL disable app-authored animation. Native system presentations SHALL follow macOS settings.

#### Scenario: System Reduce Motion enabled
- **WHEN** system Reduce Motion is enabled even with Follow System selected
- **THEN** the app uses reduced motion without large displacement, scale or bounce

#### Scenario: App animation disabled
- **WHEN** the user selects Off
- **THEN** app-authored transitions apply immediately while all controls, feedback and flows remain available

#### Scenario: Interrupt transition with selection change
- **WHEN** a user rapidly changes rule selection during an inspector transition
- **THEN** obsolete presentation changes are superseded without stacked animation, lost edits or stale inspector state

# Folder Master — UI, UX, animations and transitions

Version 0.1 · 11 November 2026 · Experience contract. UI/UX and motion are explicit user priorities, not an end-stage styling task. The synthetic native storyboard now includes confirmed saved-plan samples, read-only draft testing, failed/partial outcomes, boundary pause/cancel, history inspection and inverse previews; [observed evidence](UI_STORYBOARD_EVIDENCE.md) distinguishes these from real execution. Complete state, motion, accessibility and real-engine UX acceptance remain open in PROGRESS.md.

Related: [goal](GOAL.md), [PRD](PRD.md), [flows](USER_FLOWS.md), [control catalog](USER_OPTIONS.md), [technical design](../openspec/changes/build-folder-master/design.md).

## 1. Experience principles

1. **Make automation understandable.** Put folder scope, saved rule order, matching explanation and resulting path near the decision. Use familiar verbs and concrete filenames; make advanced syntax optional.
2. **Separate editing, preview and execution.** Drafts stay drafts; previews explain effects; Run Selected commits an explicit saved plan. Show one primary action per step and contextual secondary actions.
3. **Keep the person oriented.** Preserve selection, scroll position and keyboard focus across scans, edits and history updates. Let changes settle near the initiating control instead of navigating unexpectedly.
4. **Make status truthful.** Pending, working, partial, canceled, needs-review and successful states are distinct. Success appears only after engine acknowledgement; a paused app can still be finishing its current step.
5. **Use motion to explain changes.** Short transitions communicate insertion, reordering, expansion and progress. The app stays fully usable with motion disabled.

## 2. Visual system and layout

**Appearance:** native macOS surfaces, semantic system colors/materials and SF Symbols; no custom web-style title bar, excessive gradients or decorative cards. Use system accent for selection/primary controls, semantic warning/error colors with text/icon equivalents, and no custom “green means safe” shortcut.

**Typography:** system font and text styles; clear window/section labels, body controls, secondary paths/help. Paths can use monospaced text in detailed inspectors when it improves comparison. Long paths truncate in lists with full value available via tooltip/copy/detail; do not hide the distinguishing destination suffix in preview. No arbitrary tiny text for destructive warnings.

**Spacing:** 8-point rhythm (4 for compact internal spacing, 8/16/24 between related/section groups). Prefer native form/control dimensions. Related condition/operator/value controls align as one row; nested groups use indentation and explicit All/Any/None headers. Use a separator rather than a new ornamental container for every row.

**Window:** initial 1100×720, minimum 820×560. Folder/sidebar width approximately 200–240, rule list 240–300, details flexible. These are starting layout values, adjusted by native usability checks. Allow sidebar collapse; critical actions stay visible or accessible in toolbar/menu; details and tables scroll. Keep editable content out of a fixed-size menu panel.

**Density:** show rule name, enable state and short action summary in the list; full conditions/actions in inspector. Disclose advanced regex, captures, format strings, script settings and limits only on request. Keep their current values visible when they affect behavior.

**Accessibility:** standard controls and focus rings; names/value/error labels; keyboard alternatives to dragging; logical tab order; no color-only status; system Increase Contrast/Reduce Transparency/Reduce Motion; readable zoom/system text preferences where supported. Focus remains within a presented sheet and returns to its invoker on dismiss.

## 3. Screen and state matrix

Every row below must have a designed and verified state; “native control exists” alone is not a UX check.

| Surface | Normal / primary action | Loading / pending | Empty | Error / blocked | Success / feedback |
| --- | --- | --- | --- | --- | --- |
| Welcome | Add Folder | Folder panel owned by macOS | No folders; local-only introduction | Selection denied/invalid | Newly added folder selected, Off state explained |
| Folders | Select folder; Preview / Run Now | Baseline indexing/reconnecting; progress text | Add Folder CTA | Offline/permission/remote/overlap reason with repair action | Stable scope status; no automatic run implied |
| Rule list | Select/edit; New Rule | Save/toggle pending acknowledgement | New Rule CTA; Idle explanation | Invalid/capability blocked with text | Saved revision feedback; focus stays on rule |
| Rule editor | Save / Test Draft | Test/extraction progress with cancel | Empty conditions/actions guide | Inline field error and summary; Save disabled | Saved check/label after acknowledgement |
| Preview | Run Selected | Progressive scan rows; canceled scan explicit | No eligible/matched files and exclusion summary | Unknown, stale, conflict and permission rows distinct | Ready selected chain summary; no fake execution success |
| Running/results | Cancel / View History | Actual step count, activity and safe pause text | No selected work cannot begin | Partial/failure/recovery distinct | Concrete effect counts and eligible Undo |
| History/undo | Inspect / Preview Undo | Paginated query/inverse validation | No activity; link to preview setup | Undo unavailable reason; original/output reveal | Undo appended; original history remains visible |
| Settings | Edit validated choice | Save/login approval pending | Not applicable; defaults visible | Inline bounds/system permission explanation | Acknowledged saved settings; state mirrors OS |
| Status menu | Pause/Resume / Open | Working or Pausing with count | Idle/No enabled rules | Needs Attention with accessible label | Stable status; no constantly spinning idle icon |

Each screen has a primary/secondary action order. Critical cancellation is always reachable during loading. Avoid modal alerts for every file: aggregate problems in preview/history and show one actionable error banner where appropriate. Destructive/restricted acknowledgement uses explicit scope/count language and no ambiguous “OK.”

## 4. Interaction contracts

- **Rule creation:** provide blank rule plus inline examples/help rather than silently installing live templates. Add Condition/Group and Add Action menus use the exact catalog labels. Default disabled state and first-match behavior stay visible.
- **Editing:** local input feels immediate; validation identifies field and reason. Save state progresses Unsaved → Saving → Saved only after persistence acknowledgment. Escape/cancel preserves previously saved behavior. Navigation prompts only when edits would be lost.
- **Preview comprehension:** row detail explains condition truth, text completeness, action order, exact path changes and undo limitations. Show source/destination as a before→after comparison. Whole-file chain selection prevents accidental execution of a dependent subset.
- **Execution feedback:** distinguish queue, reading/OCR, applying and recording result. Use determinate progress only when total is known; otherwise native indeterminate activity with phase text. No invented ETA or percent.
- **Recoverability:** pair errors with the next valid action (refresh, reconnect, inspect, retry through preview). An Undo label appears only where an eligible inverse can be validated. Permanent delete/script limitations appear before commit.
- **List updates:** batch background inserts; do not jump selection to newest item or reorder the active row under the pointer. Preserve visible scroll anchor. User explicitly chooses newest/sort/filter changes.
- **Notifications:** avoid success notification per file; use selected summaries/errors. Never show document text in system notifications. In-app history is the durable reference.
- **Repeated/fast input:** a second click while saving/running cannot duplicate commands; selection changes cancel obsolete view requests. A newer state supersedes older animation/response IDs. Escape closes a sheet only when its documented cancel semantics are safe.

## 5. Motion tokens and policy

These are proposed targets, not measured results. Use native macOS menu/sheet animation as supplied by the system. App-authored motion is subtle and explicit.

| Token | Target | Use |
| --- | --- | --- |
| Immediate | 0 ms | Off mode, urgent error/pause/command availability, direct text entry |
| Quick | 120 ms, ease-out | Local feedback/opacity and inspector content replacement |
| Standard | 180 ms, ease-in-out or native equivalent | Disclosure expansion, user-added row and small structural layout change |
| Context | 220 ms, ease-out | Preview→results/detail stage change where context benefits |
| Maximum | 300 ms | Upper bound for app-authored transitions; not an artificial wait |
| Reduced | 0–100 ms opacity or immediate | No displacement, scale, spring/bounce or large movement |

Setting: Follow System (default), Reduced, Off. Effective policy is the more restrictive of system Reduce Motion and app selection. Off disables app-authored animation; OS-owned panels/menus follow macOS settings. There is no “force full animation” override of system accessibility preferences.

No decorative looping effects, parallax, 3D, confetti, shaking errors or pulsing status icon. Native progress may animate only while actual work is pending. Text/state changes remain legible without motion; Reduce Motion does not hide progress or error feedback.

## 6. Transition matrix

| Trigger / transition | Normal app motion | Reduced / Off | State/focus invariant |
| --- | --- | --- | --- |
| Select folder/rule | Quick inspector opacity; preserve list selection | Brief fade / immediate | No scroll reset; dirty-draft guard runs before selection commit |
| Add condition/action/group | Standard local insertion + height expansion; focus new field | Fade / immediate layout | New element announced; existing input values stable |
| Remove editor row | Standard local collapse after explicit deletion | Fade / immediate | Focus next logical control; row deletion is config only |
| Reorder rule/action | Standard short relocation/settle; no overshoot | Immediate order change + accessible announcement | Same stable row ID/focus; no engine effects caused by animation |
| Toggle enabled | Native control feedback; pending text until acknowledgement | Same accessible state / immediate | Failed save restores actual state with error; no false running state |
| Open preview/run/undo sheet | Native system presentation | System accessibility behavior | Focus contained; return to invoker; avoid double animation |
| Scan results stream in | Batch append without animating every row; Quick count update | Immediate | Preserve scroll anchor, selection and readable count |
| Expand preview explanation | Standard local disclosure | Fade / immediate | Explanation available to VoiceOver immediately |
| Run begins | Context content transition to working status | Brief fade / immediate | Primary action disabled before any cosmetic transition |
| Progress / phase update | Native indicator; coalesced numeric/phase updates | Same truthful feedback | Never infer total/ETA; cancel remains responsive |
| Pause/resume | Quick state-label change; explicit Pausing until safe boundary | Immediate | No delay to command dispatch, no optimistic pause completion |
| Partial/error result | Immediate error text; optional Quick surrounding detail fade | Immediate | Announce material error; no shake/auto-dismiss |
| Success result | Context change and concise native check icon | Brief fade / immediate | Only after durable engine outcome; no animation callback advances execution |
| Undo completed | Quick history row update with restored-path explanation | Brief fade / immediate | New audited item, preserve selected original record |
| Cancel/close/interruption | Cancel pending transition from present visual state | Immediate | Command cancellation and focus restoration independent of animation completion |

Background bulk scans/history pagination do not animate thousands of rows. Coalesce noncritical progress updates to at most 4 Hz; final/error/cancel states remain prompt. A fast selection/change interrupts the current transition instead of stacking animation queues. UI timers/animations never schedule filesystem action chains.

## 7. Storyboard and early delivery

M1 must demonstrate these synthetic, clearly labeled presentation states before broad engine implementation:

1. Welcome → local folder setup → Off folder with empty rule list.
2. Add rule → nested conditions/actions → invalid field → corrected draft → save feedback.
3. Test/preview → mixed Ready/Unknown/Conflict rows → inspect explanation → selected run confirmation.
4. Working → pause pending → partial error/results → history → safe undo preview.
5. Same sequence with system Reduce Motion and app Off; keyboard-only interaction and VoiceOver labels.

These screens can initially use synthetic view-model data after the planning review; simulated file results must be visibly marked. Replace synthetic providers through the existing state/command interface, preserving interaction behavior. Do not build a separate web UI or commit a throwaway mock as if it were the product.

## 8. Acceptance and evidence

| Check | Acceptance evidence |
| --- | --- |
| Visual state coverage | Captures of the screen/state matrix in light/dark at initial/minimum sizes; explain any missing state |
| Guided usability | A first-time evaluator can add a folder/rule, explain preview, run, locate history and attempt supported undo without terminal use or author coaching; record confusion and fixes |
| Options discoverability | Every option catalog row maps to a visible labeled control/help; disabled controls explain why |
| Keyboard / VoiceOver | Complete primary journeys, reorder without drag, preserve/restore focus and announce state/error changes once |
| Motion normal/reduced/off | Record designated transitions and rapid interruptions in each policy; no prohibited movement in reduced/off, no stranded focus or wait for animation |
| Truthful feedback | Slow/failing engine simulation and real fault fixtures never show successful file effects before acknowledgment |
| Performance | p95 common interaction under 100 ms under scan; measure app transitions against target durations; on 60-Hz baseline target p95 animated frame interval ≤16.7 ms for small designated transitions, report actual traces and bulk-list exceptions |
| Native integration | macOS-owned menu/panel behavior, close-vs-Quit, system accessibility/contrast and minimum supported OS checks |

The first-time evaluator walkthrough is a validation task, not a claim of completed user research. If no evaluator or measurement environment is available, leave that evidence Not run. A static screenshot cannot prove animation quality; animation recordings cannot prove file safety. Both experience and engine acceptance are required.

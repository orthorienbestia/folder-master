# Rule compiler — task 2.4

The existing structural decoder stays suitable for reading old revisions. New validation and saves must also compile all patterns, rename replacements and templates before writing a revision. Invalid historical patterns remain editable rather than making the store unreadable.

1. Reuse the bounded Rust regex/glob compiler. Compile content regex syntax without claiming extraction/evaluation integration. Return stable condition/action IDs and field paths with actionable errors.
2. Compile only catalog tokens and date-format components. Capture tokens bind an explicit regex predicate under All ancestors; check group names, scope and source. Separate ZIP filename and destination bindings.
3. Expand pure supplied facts into bytes. Keep non-UTF-8 filename components lossless. Reject missing dates/extension/capture/counter, incomplete text captures, NUL/separators in token values, and unsafe final filename/relative path. Actual volume constraints and descriptor-relative containment remain preflight/executor responsibilities.
4. Implement literal/regex replacement first/all, with checked capture references and literal dollar escaping. Preserve an existing extension once. Bound pattern/template/expanded bytes and counter padding (1–20 decimal digits) to prevent unbounded expansion.
5. Assign counters from sorted relative-path bytes, rejecting duplicates and overflow. This is pure plan assignment; durable commit reservation remains required when the planner/journal/executor is connected.
6. Display compiler errors by node in the real rule editor, clear stale errors on edit/navigation, and keep draft/revision intact after rejection. Synthetic storyboard controls stay explicitly synthetic.
7. Verify invalid-save non-mutation through worker and typed store, old invalid-pattern repair, token/date/capture/traversal/byte-name/replacement/counter boundaries, native state and both architecture builds. Review scope and commit locally. Check 2.4 only when its named compiler contracts pass; do not imply operational planning or reservation has shipped.

Initial red evidence: build/compiler-storage-red.log and build/compiler-bridge-red.log show invalid regex accepted as revision 2 and validate_rule reporting valid=true, respectively.

## Verified checkpoint — 12 November 2026

Task 2.4's compilation and pure output contracts pass, including Save rejection without revision advance and historical invalid-pattern repair. Review regressions fixed repeated-extension/trailing-dot loss and unmatched Unicode normalization. Native controller regression and isolated-window inspection verify retained draft/revision, inline condition feedback and first-error scrolling; sample copy and user-facing banner were corrected afterward.

`make test presentation-smoke rule-persistence-smoke check universal` passed: 81 Rust / 45 native tests, zero failures, one existing physical invalid-UTF-8 fixture skip; the 72 native configuration fixtures still pass. See PROGRESS.md and UI_STORYBOARD_EVIDENCE.md for evidence boundaries. Counter values are deterministic proposals only until journaled execution reserves them; no filesystem planner or effects are implied.

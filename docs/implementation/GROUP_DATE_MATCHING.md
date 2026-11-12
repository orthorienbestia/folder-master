# Dates, tags, labels and groups

Implement task 2.3 on the pure metadata evaluator. Keep file discovery, content matching, the complete save-time compiler, planner and effects as separate required tasks.

1. Extend snapshots with four independent date sources, known/unavailable tags and a known/unavailable Finder label. Add no Created fallback for missing Added/Last opened fields.
2. Evaluate exact tag names using a bounded Unicode/NFC regex set (one compiled set per predicate); keep commas, spaces and case options literal. Label None is a real known value, distinct from missing metadata. Never infer label from named tags.
3. Capture a native Gregorian calendar context with explicit now/timezone, half-open Today/Yesterday windows and requested On-date windows. Native Calendar handles DST/midnight changes. Rust consumes captured facts only; no ambient clock/timezone or timezone-database dependency. Missing/skipped calendar dates produce unavailable windows, not normalized dates. Capture rounds the clock to milliseconds before deriving its day.
4. Date before/after and age are strict; ranges inclusive. Compute timestamp differences in i128 and compile canonical stored-decimal age boundaries into integer floor/fraction values, avoiding float timestamp/unit math. Calendar day length is independent of 24-hour elapsed days. Missing required clock or unavailable/invalid calendar facts yield Unknown. Yesterday selects the preceding existing local day.
5. Compile metadata condition trees after existing root/depth/leaf/identity validation. All/Any/None use three-valued logic, stop at decisive branches, retain evaluated evidence and skipped subtree IDs. Unsupported content predicates remain compile errors until their content milestone; no unsupported predicate silently becomes False.
6. Verify all operators/sources, complete ternary truth tables, known-empty versus missing values, timezone/DST, strict boundaries, fractional ages and source independence. Test native calendar facts and cross-language JSON shape. Review, run regression/native/OCR/universal checks, update OpenSpec and commit locally.

There is still no filesystem evaluation, actual Preview/Run Now, automatic eligibility or scheduling from this work. Complete UI/accessibility/motion and platform gates remain open. Task 2.3 is checked only after the named predicate/group contracts pass.

## Verified checkpoint — 12 November 2026

Seven initial Rust and three native contracts failed against stubs. Twelve date/tag/label/group tests now pass, including all 27 ternary pairs, field independence, nested/invalid trees, skipped IDs, shared native facts, all elapsed units and strict boundaries. Native Calendar tests prove DST and skipped-day behavior. Six captured contexts regenerate identically; both languages read the same JSON fixture.

Review's numeric precision question led to a reproduced 0.009-minute drift at 540 ms. The earlier 0.00005 example did not reproduce in Rust. Canonical decimal compilation resolves the actual failure; huge/subnormal/signed-zero cases pass, and follow-up review found no remaining issue.

`make test presentation-smoke rule-persistence-smoke check universal ocr-proof` passed: 70 Rust / 44 native tests, zero failures, one existing physical invalid-UTF-8 fixture skip, 72 native configuration fixtures, both architectures/minos14 and local signature, plus direct-network-denied OCR. Task 2.3 is complete; operational integration and full UI date-picker granularity/accessibility/motion acceptance remain open.

# Folder Master — Active project goal

Updated 11 November 2026 from the user's original app request and subsequent Git/UI/UX instructions.

**Build a polished native macOS 14+ menu bar file organizer, using a Rust engine and SwiftUI/AppKit interface, with local-only processing and strong UI/UX, animations and transitions.**

Watch one or more user-selected local folders. Match by filename, extension, kind, size, date, Finder tags/color labels and text, including on-device OCR for images/scanned PDFs. Support move, copy, rename, tag, compress/uncompress, Trash, permanent delete and restricted local custom scripts. Include folder/rule management, menu controls, dry-run preview, Run Now, local history and supported undo. Distribute directly outside the Mac App Store.

Before implementation, deliver a reviewable PRD, TDD, complete user flows/options, UI/UX/motion design and OpenSpec scenarios/tasks. Use Git to organize changes and evidence-based progress. Treat native visual quality, progressive disclosure, responsive feedback, deliberate transitions and reduced-motion accessibility as acceptance requirements throughout development.

## Success includes experience quality

- A person can configure, preview, enable, inspect and recover supported automation through clear native flows.
- Every primary screen has designed initial/loading/empty/error/success states and stable focus/selection behavior.
- Animations explain changes, never conceal errors or delay commands, and respect system Reduce Motion and app Reduced/Off settings.
- Preview and result feedback remain truthful to actual engine acknowledgements; simulated prototypes are labeled.
- File safety, offline boundaries, recovery, runtime correctness and UX are verified independently.

Canonical details: [PRD](PRD.md), [UI/UX and motion](UI_UX_DESIGN.md), [TDD](../openspec/changes/build-folder-master/design.md), [tasks](../openspec/changes/build-folder-master/tasks.md), [progress](PROGRESS.md).

The app-build goal remains active. The available Codex goal tool supports status changes only, so this tracked brief records the user's expanded objective without falsely completing/recreating the active goal.

# Folder Master — User-visible options

Status: proposed 1.0 contract · 11 November 2026. Defaults below are product decisions for review. See [PRD](PRD.md), [flows](USER_FLOWS.md), and [TDD](../openspec/changes/build-folder-master/design.md).

## 1. Folder setup and management

| Control | Options / values | Default and validation |
| --- | --- | --- |
| Add Folder | Native choose-directory panel; one at a time, repeat for multiple | Local volumes only; no preauthorized folders; reject remote mounts, files, system locations, app data/temp/Trash roots, aliases/symlinks and overlapping watch scopes |
| Folder display name | Optional editable nickname | Actual folder name; path remains visible in details |
| Automation | On / Off | Off on addition; enabling without enabled rules shows Idle |
| Include subfolders | On / Off | Off; packages are never traversed |
| Include hidden files | On / Off | Off; app-owned data and in-flight temp files always excluded |
| Exclusions | Relative path glob list; add/remove/reset | Partial extensions excluded; glob syntax help and example; validation before save |
| Watch mode | Automatic / Polling | Automatic chooses native events on supported local volumes; Polling for unsupported local volumes only, with explicit reliability notice; remote mounts rejected |
| Polling interval | 5–3600 seconds, integer | 30 seconds when polling |
| Reconnect | Folder chooser | Require same identity where available; changed identity requires confirming replacement; automation stays paused until resolved |
| Context actions | Reveal in Finder, Preview, Run Now, Pause/Resume, Rename Display Name, Duplicate Rule Into…, Remove Folder | Remove confirms settings/rule removal only; in-progress chain drains; files/history retained |

Cloud-resident placeholders are skipped. The app offers no “download cloud files” switch in 1.0. A local cloud-synced folder may still sync through other software; destination chooser discloses this boundary if detectable.

## 2. Rule editor and lifecycle

| Control | Options / values | Default and validation |
| --- | --- | --- |
| Rule name | Required text up to 200 characters | “Untitled Rule” draft; whitespace-only rejected |
| Enabled | On / Off | Off for new/duplicated drafts; capability acknowledgements required before enable |
| Conditions | All / Any / None; Add Condition; Add Group; delete row/group | Root All; maximum 3 group levels, 50 leaf predicates; empty groups invalid |
| Action list | Add Action, remove, move up/down or drag | At least one; maximum 20; actions after terminal action rejected |
| Rule behavior | Stop after match / Continue to next rule | Stop; terminal actions force stop |
| Test Draft | Choose sample file(s) or preview folder | Uses unsaved draft only; does not execute scripts or mutate files |
| Save / Cancel | Save current revision / discard draft | Validation inline; changing selection prompts Save / Discard / Keep Editing |
| List actions | New, Edit, Duplicate, Duplicate Into Folder, Move Up/Down, Enable/Disable, Delete | Delete confirms config removal; no user file deletion |

Saving an enabled rule creates a new immutable revision; existing started chains complete their pinned revision unless pause/disable/capability revocation stops new steps, and queued candidates replan. Reordering invalidates applicable previews. No live mutation while typing. Enabling/saving time rules baselines already-true historical conditions without running them; Run Now applies those files explicitly.

## 3. Condition catalog

Text fields use literal strings by default. Toggle case sensitivity for name/tag/text conditions; default insensitive Unicode comparison. Regex is opt-in, Rust regular-expression syntax, validated when saving; no backreferences or look-around promised. Optional named captures feed rename templates; unmatched/ambiguous captures invalidate that action. A “does not” operator or None group never turns unavailable data into a match.

| Field | Operators | Value / special controls |
| --- | --- | --- |
| Name | is, is not, contains, does not contain, begins with, ends with, glob, regex | Scope: filename with extension (default) / stem; optional case sensitivity |
| Extension | is one of, is not one of, is empty | Comma-separated final extensions, optional leading dots normalized; case-insensitive; `tar.gz` has final extension `gz` in 1.0 |
| Kind | is / is not | Document, Image, PDF, Audio, Video, Archive, Other; optional explicit UTType identifier; platform type conformance, not translated Finder description |
| Size | equals, less than, greater than, between inclusive | Nonnegative numeric value(s); bytes, KiB, MiB, GiB; integer bytes after conversion; invalid/reversed ranges rejected |
| Date | before, after, on calendar date, in date range, older than, newer than, Today, Yesterday | Created / Modified (default) / Last opened / Added to folder; absolute date/time or elapsed minutes/hours/days/weeks; unavailable metadata = unknown |
| Finder tags | contains any, contains all, contains none, is empty | Tag name picker + type new values; exact names with optional case sensitivity; tag absence distinct from read failure |
| Finder color label | is one of, is not one of | None, Gray, Green, Purple, Blue, Yellow, Red, Orange; displayed independent of tag-name criteria |
| Text content | contains, does not contain, regex | Source: embedded/text only (default), embedded then OCR if needed, force OCR; optional case sensitivity; complete extraction required to decide absence |

“Added to folder” uses platform metadata when available; absence does not fall back silently to Created. Last opened is best-effort metadata, not an access audit. Date ranges are inclusive at selected granularity; before/after and older/newer are strict comparisons. Calendar controls show timezone; elapsed “days” are 24-hour durations. Missing values show Unknown and an explanation in test/preview.

Name comparisons normalize the selected filename/stem and entered pattern to Unicode NFC. Insensitive matching uses Unicode simple case folding, independent of locale; it does not expand ß to `ss` or apply compatibility normalization. Regex uses Rust syntax against the normalized name (search unless explicitly anchored). Filename globs match the whole selected name: `*` means zero or more Unicode scalars, `?` one scalar, `[abc]`/`[a-z]` classes/ranges, `[!abc]`/`[^abc]` negation, `{a,b}` alternatives and backslash escapes for literals. Brace alternatives may nest to depth 16; consecutive stars have the same filename-only meaning as `*`. Globs do not traverse directories or accept separators. Patterns are limited to 16 KiB UTF-8; compiled regex/NFA and DFA cache budgets are 1 MiB each. Invalid/over-budget compilation is an error, never a match. Unreadable or non-UTF-8 selected components are Unknown rather than lossy text. Extension input already lowercases during entry; observed extensions use the same Unicode lowercasing before NFC/simple-fold comparison, preserving that saved-value contract.

Kind categories use native UTType conformance independently and may overlap. Document covers text, composite content, spreadsheets, presentations and PDF; Video covers movie types (including video-only subtypes). Other means a known type outside the recognized categories, not unavailable metadata. Explicit UTType criteria require a resolved platform conformance answer; an unsupported or unrequested answer remains Unknown even for “is not.” Filename extensions never substitute for kind facts.

Group results use three-valued logic: All is false if any false, otherwise unknown if any unknown; Any is true if any true, otherwise unknown if any unknown; None negates Any with unknown preserved. Unknown rules are skipped with reason. A later independent rule can still match the file.

## 4. Action catalog

Common destination options: selected absolute root, optional relative subfolder template, create missing subfolders On (default)/Off, and conflicts Keep both (default)/Skip/Ask. No overwrite option. Empty or escaping paths, separators in filename tokens, empty names, NULs, and output equal to source are rejected or explicit no-op as appropriate. Normal filesystem length/case/Unicode constraints are checked for the actual volume. Conflict review permits Skip / Keep both / choose another destination, never silent replacement.

All selected roots/destinations/interpreters/export paths must be on local mounted volumes; remote mounts are rejected. Preflight the entire chain's guarded capabilities before any effect. Tag/label updates on multiply hard-linked files are blocked because metadata changes could affect an unselected link. Move/rename/delete operate on only the selected directory entry and do not claim to erase other hard links.

| Action | All action-specific controls | Default / limits |
| --- | --- | --- |
| Move | Destination and common options | Updates current path; completes approved remaining actions at destination; ends later rules when outside original scope |
| Copy | Destination and common options | Keeps source as current; output recorded separately |
| Rename | Mode: template / find-replace; literal find or regex; replace first/all; preserve extension toggle | Template `{stem}`; preserve extension On; extension appended once; find required in replace mode |
| Tags / label | Tags: add/remove/replace; list of tag names. Label: leave unchanged/set a color/clear | Add; leave label unchanged; at least one change required; replacement explicitly confirms loss of existing tag names |
| Compress | Format ZIP; output destination; archive filename template; conflict options | `{stem}.zip`; originals retained; no password/encryption option |
| Uncompress | ZIP only; output destination; output subfolder template; conflict options | `{stem}` subfolder; extraction terminal; reject encrypted/unsafe/unsupported entries |
| Trash | Terminal action indicator | System Trash; no permanent-delete fallback |
| Permanently delete | Required nonrecoverable acknowledgement and rule capability | Globally disabled until explicitly enabled; terminal; no secure erase |
| Custom script | Choose local script/executable; interpreter: zsh/sh/executable/custom locally installed; literal argument list; timeout 1–600 seconds; optional publish-output root | 30 seconds; terminal; globally disabled until enabled; no original-path mutation or network; no automatic retry; no script Undo |

Rename/subfolder tokens: `{name}`, `{stem}`, `{ext}`, `{created:yyyy-MM-dd}`, `{modified:yyyy-MM-dd}`, `{now:yyyy-MM-dd}`, `{counter:3}`, `{capture:name}`. Date format support is an allowlisted subset (`yyyy`, `MM`, `dd`, `HH`, `mm`, `ss` and literal `-`, `_`), shown in the token picker. Preview captures plan time; counters are per action/destination prefix and commit-reserved; Keep both collision suffixing is separate. Batch enumeration is sorted by relative path bytes before counters are assigned. Empty extensions/captures and unavailable dates must produce explained validation failures rather than guessed tokens. Regex capture tokens reference an explicitly chosen matching condition; captures are unavailable under ambiguous Any/None branches.

Script inputs: staged working-file path as an argv entry, metadata manifest path, working/output directory paths; paths are never interpolated into shell code. Literal argv only; no evaluation of user file text as commands. Source snapshots copied into the service container; outputs published only after successful exit and validation. A **Test Script** command is explicitly an execution, on disposable staged samples, with the same isolation and capability confirmation; it is separate from Test Draft/dry run. Output logs capped at 1 MiB; script input changes reset the saved approval hash.

## 5. Content and OCR settings

| Control | Options | Default / bounds |
| --- | --- | --- |
| OCR master switch | On / Off | On; only invoked by OCR-enabled text conditions |
| Recognition | Accurate / Fast | Accurate |
| Languages | Auto-detect or ordered language list from installed runtime support | Auto-detect; unsupported choices prevented; never download models automatically |
| Language correction | On / Off | On where supported; help explains OS/language limitations |
| PDF OCR policy | Pages without usable embedded text / all pages for force OCR | First option; mixed pages that have some text but scanned regions need force OCR for those regions |
| Text-cache persistence | Off / On | Off; On retains extracted text locally up to 7 days / 100 MiB; user can clear now |
| Max content input | 1–1024 MiB | 100 MiB; larger files get Content unavailable, not false match |
| Max PDF pages | 1–1000 | 100; exceeding produces incomplete extraction |
| Max extracted text | 1–50 MiB | 10 MiB; truncation is explicit |
| Per-file OCR timeout | 1–600 seconds | 60 seconds; timeout = incomplete/unknown where needed |

Image OCR 1.0: PNG, JPEG, TIFF and HEIC if locally decodable; multipage TIFF processes all frames within page limits. PDFKit handles PDFs. Embedded extraction: UTF-8 plain text and PDF page text only; Office documents, arbitrary binary formats, UTF-16, and rich document parsing are outside 1.0. A successful complete extraction of a supported empty file differs from unsupported/failed extraction. Maximum raster size is 20 megapixels per image/page, downsampled locally; OCR accuracy is not guaranteed. No source rewriting, sidecar files, or searchable-PDF export.

Automatic language detection uses Accurate recognition. Fast requires an explicit ordered selection from its runtime-supported languages; the interface must explain this dependency rather than silently default to another language. Language correction remains subject to language/OS support.

## 6. Preview and Run Now

| Control | Behavior |
| --- | --- |
| Scope | Selected folder / all enabled folders; a paused selected folder can be run once explicitly |
| Rules | Enabled saved rules in order; editor Test Draft substitutes only that draft and has no Apply button |
| Preview columns | Selection, filename/path, rule, match explanation, ordered effects, destination, conflicts, reversibility, readiness |
| Filter | All / matched / no match / unknown or skipped / needs review / failed |
| Row detail | Metadata snapshot, condition tree results, predicted current/secondary files, text/OCR status; transient matched-text reveal |
| Selection | All ready file rows / none / individual rows; entire per-file chains, no arbitrary internal action selection |
| Refresh | Rebuild plan with current rules/files; previous selection retained only for still-equivalent rows |
| Run Selected | Saved-rule preview only; revalidate rows and confirm irreversible actions; paused scope requires Run once while paused |
| Cancel preview | Close without source/destination mutations; cancel queued content work |
| Cancel run | Stop new steps at safe boundary; show retained completed effects and eligible undo |

Script nodes show “Would execute — effects unknown.” They never run during preview, and later dependent effects are not invented (script is terminal). Stale rows become Needs refresh. Previewing does not grant execution permission. A scan may read metadata/content and change OS access timestamps as a normal read side effect; it never intentionally edits user metadata, creates destination directories or executes action code.

## 7. History, undo and data controls

| Control | Options / behavior |
| --- | --- |
| History scope | All folders or selected folder; path/rule-name search; date range |
| Status filter | Succeeded, Partially completed, Failed, Skipped, Needs review, Canceled, Undo succeeded/failed, Recovery required |
| Event detail | Trigger, run/rule revision, condition explanation without persistent document text, step times, paths, output manifest, error, undo eligibility |
| Reveal | Current output / original location if present; disabled if missing |
| Undo | Selected operation/file chain; preview inverse steps and conflicts; confirm; reverse dependency order; blocked when not safe |
| Undo conflict | Show reason; reveal affected item; retry after user resolves; no force overwrite option |
| Retry failed | Replan current eligible file through preview; explicitly execute scripts only by new confirmation |
| Export history | Native Save panel; JSON/CSV; selected filters or all; includes paths warning; script logs excluded by default |
| Clear history | Confirm; completed selected/all records; show lost undo eligibility; unresolved journals retained |
| Retention | 1–365 days and 1k–1m action records; defaults 30 days / 100k records |

Retention defaults are 30 days / 100k records; the first bound reached wins for completed records. Persisted content cache and script staging have independent limits/cleanup. Undo is a new audited operation, never removal of the original history. An unsupported action in a chain is an undo barrier; the UI offers only a safe reversible suffix after that barrier, with supported earlier actions inspectable individually only after dependency validation. No Redo in 1.0.

## 8. Menu bar and Settings

| Surface | Choices / behavior | Default |
| --- | --- | --- |
| Menu status | Running / Idle / Paused / Working / Needs Attention; active count | App state, no content/path in icon |
| Global automation | Resume / Pause indefinitely / Pause 15 minutes / Pause 1 hour | Persist paused state; timed deadline persists across restart |
| Folders submenu | Folder toggle, nested enabled-rule toggles, Run Now | Reflect saved states; unavailable folder cannot be enabled |
| Quick actions | Open Folder Master, Preview…, Run Now…, Recent Activity, Undo Last Eligible…, Settings…, Quit | Destructive effects never triggered just by opening menu |
| Launch at login | On / Off; current system approval state and link | Off; no daemon/plist installation |
| Notifications | Errors only / summaries and errors / Off; OS permission state | Errors only, opt-in OS request at first enable |
| Global capabilities | Allow permanent-delete rules / Allow restricted script rules | Both Off; per-rule opt-in still required |
| Processing | Low-impact mode On/Off | On; one mutation worker, one content/OCR worker |
| Privacy | Clear text cache; open local data folder; export history; view script data; clear completed history | No telemetry/network toggle because there is no network feature |
| Appearance | Follow system | Native system fonts/materials; no custom theme engine |
| Motion | Follow System / Reduced / Off | Follow System; system Reduce Motion is always the minimum reduction; Reduced uses brief opacity/immediate changes, Off disables app-authored animation; native system panel motion follows macOS |
| Help / About | Local help, version, licenses, permission explanation, undo/privacy limitations | Packaged offline; external documentation opens only on explicit user action |
| Reset application | Confirm stop automation; choose settings only / settings and completed history/cache | Never delete watched/destination files; preserve unresolved recovery journals |
| Quit during work | Quit after current safe step / Cancel quitting | Explain active work; no force termination UI |

Pause is enforced at action boundaries, and the UI shows “Pausing — current step finishing” when necessary. Manual Run Now does not resume automation or change toggles. All UI controls have accessible labels, focus states, keyboard activation and error descriptions; rule reordering has menu commands as well as drag gestures.

Animation types, durations, focus rules and screen-state acceptance are defined in [UI_UX_DESIGN.md](UI_UX_DESIGN.md). Motion does not gate command completion or filesystem correctness, and progress reflects acknowledged engine state.

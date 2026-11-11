# Platform research and evidence

Checked 11 November 2026. Primary documentation initially supported planning; the Rust/native foundation now has build and limited runtime evidence recorded in PROGRESS.md. The user selected Rust engine + SwiftUI/AppKit UI and direct distribution. Unimplemented platform recommendations below remain design inferences rather than runtime proof.

## Native UI and lifecycle

- Apple documents `MenuBarExtra` as a persistent status-area scene, composable with an app window; `LSUIElement` supports accessory-style presence. This supports a native window plus menu utility on the target OS. [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- `SMAppService` is available from macOS 13, exposes `mainApp`, registration/unregistration and status, and is subject to system approval. Use it for opt-in login launch on macOS 14+. [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

## Watcher reliability

- Apple's FSEvents guide says coalesced/dropped events can require recursive rescans, and monitoring should begin before initial enumeration to avoid missing concurrent changes. Design therefore treats events as hints and reconciles snapshots. This is archived foundational guidance, not a current Rust API reference. [Using the File System Events API](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html)
- Context7 CLI resolved official Notify repository `/notify-rs/notify`, listing stable version `notify-8.2.0`. Retrieved docs describe macOS rename ambiguity/rescan events and polling as fallback for filesystems without usable events. Some snippets referenced the moving `main` branch; revalidate exact APIs against the pinned release during M1. [Notify repository documentation](https://github.com/notify-rs/notify), [maintainer event guide](https://github.com/notify-rs/notify/wiki/The-Event-Guide)

Documentation lookup used the requested Context7 CLI outside the default sandbox: one `library` resolution and one focused `docs` request. No API keys or private paths were included in external queries. Apple pages with JavaScript-only responses were read through their linked Markdown versions.

## Local document text and OCR

- Apple states Vision processing occurs on the user's device and supports offline text recognition, fast/accurate recognition and language-related configuration. This supports the local OCR requirement. The app still needs testing for accuracy, supported runtime languages and resource bounds. [Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- `VNRecognizeTextRequest` exposes recognized observations and language/recognition settings. Choose APIs available on macOS 14 and query supported languages at runtime. [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- `PDFPage.string` exposes page text. Inference: try embedded page text first, rasterize pages requiring OCR separately; this property alone does not perform OCR. [PDFPage.string](https://developer.apple.com/documentation/pdfkit/pdfpage/string)

## File metadata, Trash and access

- Foundation exposes mutable tag names and label numbers separately. This is sufficient to plan native metadata adapters; exact Finder color/tag coupling and cross-volume behavior need roundtrip tests. No undocumented xattr format is assumed. [URLResourceValues.tagNames](https://developer.apple.com/documentation/foundation/urlresourcevalues/tagnames), [URLResourceValues.labelNumber](https://developer.apple.com/documentation/foundation/urlresourcevalues/labelnumber)
- `FileManager.trashItem` returns the resulting Trash URL; Apple notes the actual filename can change. Retain that returned location and identity for conditional undo. [trashItem(at:resultingItemURL:)](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
- Security-scoped bookmarks provide persistent resource access for sandboxed apps with appropriate entitlements. The proposed host is not sandboxed, so do not misrepresent a plain bookmark as bypassing TCC or automatically enabling an XPC helper's access. [Security-Scoped Bookmark and URL Access](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)

## Offline script execution

- Apple describes XPC services as separately sandboxable components for privilege separation and stability; each service has its own sandbox, unlike merely spawning a process from the host. This supports selecting a signed sandboxed service as an isolation boundary. It does **not** prove arbitrary scripts/interpreters can run safely in the proposed configuration. An early signed integration spike must test normal execution, child sandbox retention, network/IPC denial and staged-output publication. [Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)

No unrestricted host-process script fallback is acceptable under the chosen privacy contract. Input staging and restricted outputs are product decisions to make that contract concrete.

## Direct distribution

- Apple describes Developer ID signing/notarization for direct macOS distribution. Plan a hardened, signed app and a stapled notarization ticket; this is a developer release operation, not a runtime document upload. [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- Apple's command-line workflow describes `notarytool` and stapling; ZIP files themselves cannot be stapled, so staple app/DMG as applicable before distributing. Public distribution still needs the developer's signing identity and current validation at release time. [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## UI, UX and motion

- SwiftUI exposes the system Reduce Motion preference; Apple advises avoiding large/3D motion when enabled. The experience design follows that preference and adds app Reduced/Off modes as product decisions. [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- SwiftUI animations use presentation transactions, while transitions describe view insertion/removal. Apple's transition documentation cautions against identity-affecting changes that reset content state. The design therefore uses stable row/view identity and separates animation from engine completion. These APIs support the macOS 14 baseline; timing/easing values in UI_UX_DESIGN.md are proposed design targets. [withAnimation](https://developer.apple.com/documentation/swiftui/withanimation(_:_:)), [Transition](https://developer.apple.com/documentation/swiftui/transition)

## What remains unverified

Rust/native linking, the foundation SwiftUI symbols, universal compilation, bridge request/buffer contracts and a limited synthetic UI journey now have execution evidence. Signed XPC script compatibility, metadata/ZIP preservation, TCC/cloud-provider behavior, OCR accuracy, memory/latency, x86_64 hardware, macOS 14 runtime coverage and public release signing remain unverified. The [TDD](../openspec/changes/build-folder-master/design.md) and task list keep these gates open.

## Foundation implementation references

The Context7 CLI resolved official SwiftUI documentation and retrieved Window/openWindow plus Settings/menu scene guidance before implementation. The app uses the macOS-14-compatible scene APIs and stable view identity; native window-close persistence is still an explicit runtime check. [Window](https://developer.apple.com/documentation/swiftui/window)

The bridge follows explicit C ABI ownership and panic containment, with owned buffers and unsafe pointer contracts tested at the boundary. XcodeGen 2.46.0 source documentation was used for target settings/build scripts; its generated project is tracked. Serde JSON's typed input support is used with pinned 1.0.149, verified by compilation/tests. [Rust FFI guidance](https://doc.rust-lang.org/nomicon/ffi.html), [XcodeGen 2.46.0 project specification](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md), [Serde JSON documentation](https://docs.rs/serde_json/1.0.149/serde_json/)

## Persistence and folder setup checkpoint

Context7 CLI resolved the official `/rusqlite/rusqlite` source and retrieved backup/transaction/pragma guidance outside the default sandbox. Pinned rusqlite 0.41.1 declares Rust 1.89 compatibility, verified with Cargo package metadata and compilation. The implementation uses its bundled SQLite and online backup API instead of copying a live database file without WAL. Tests verify failed transactional migration after partial DDL, newer-schema byte preservation, reopen, immutable rule snapshots and consistent WAL-inclusive backup. [rusqlite 0.41.1](https://docs.rs/rusqlite/0.41.1/rusqlite/), [online backup API](https://docs.rs/rusqlite/0.41.1/rusqlite/backup/index.html)

Apple's `volumeIsLocal` resource value and ordinary bookmark creation support native enrollment checks and persistent location references. A rename fixture verifies bookmark resolution on this host; these APIs do not establish denied-TCC or cloud-placeholder safety by themselves. Those gates remain open. [volumeIsLocal](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeislocal), [bookmarkData](https://developer.apple.com/documentation/foundation/url/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:))

Native experiments found that Swift's direct filesystem URL constructor replaces invalid UTF-8 bytes; the Core Foundation filesystem-representation constructor preserves them through the URL boundary. The byte-level regression passes. Creating an actual invalid-UTF-8 directory on this test volume fails with EILSEQ even outside the default sandbox, so that physical fixture is skipped explicitly rather than reported as supported. [CFURLCreateFromFileSystemRepresentation](https://developer.apple.com/documentation/corefoundation/cfurlcreatefromfilesystemrepresentation(_:_:_:_:))

For the VS Code old-toolchain dialog, Context7 resolved the official rust-analyzer repository and its installation/binary guidance. It recommends a compatible analyzer when retaining an older Rust toolchain and documents installation through rustup. The repository now requests the matching component rather than changing its compiler pin. Native VS Code inspection confirmed the selected server version; see PROGRESS.md for the remaining non-blocking extension/server settings warning. [rust-analyzer installation](https://github.com/rust-lang/rust-analyzer/blob/master/docs/book/src/installation.md), [rustup installation of the server](https://github.com/rust-lang/rust-analyzer/blob/master/docs/book/src/rust_analyzer_binary.md)

# Platform research and evidence

Checked 11 November 2026. Primary documentation was read online for planning; no API was compiled or exercised. The user selected Rust engine + SwiftUI/AppKit UI and direct distribution. Recommendations below are inferences from documented capabilities, not performance or platform proof.

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

Rust/native linking, actual SDK availability for chosen implementation symbols, signed XPC script compatibility, metadata/ZIP preservation, TCC/cloud-provider behavior, OCR corpus accuracy, runtime memory/latency, x86_64 hardware, macOS 14 runtime coverage and release signing have no execution evidence yet. The [TDD](../openspec/changes/build-folder-master/design.md) and task list make these checks explicit release gates.

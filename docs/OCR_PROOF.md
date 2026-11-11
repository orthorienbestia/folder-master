# Local content adapter and OCR evidence

11 November 2026, macOS 26.6.2 arm64, Xcode 26.0.1 / SDK 26.0. The native adapter uses macOS-14-compatible PDFKit, Core Graphics, ImageIO and Vision APIs. It is compiled into the app but **not connected to watched-file rules or the Rust planner yet**.

## Reproduce

```sh
make test
make ocr-proof
```

`DocumentText` in `native/PlatformAdapters/DocumentText.swift` accepts caller-supplied bytes and typed options; it opens no source URL, writes no document and retains no persistent text cache. It is a synchronous worker API and must run away from the UI actor. File eligibility, cloud-placeholder checks, stable snapshots, Rust matching/cache integration and user controls remain separate work.

The `OCRProof` scheme builds a separate App Sandbox application with no network entitlement. Its Python launcher creates a reachable loopback listener and verifies a successful control connection. The proof process's connection attempt fails with EPERM before it performs synthetic content extraction. The Mac's network interfaces remain enabled; this is process-level direct-network denial, not a system-wide packet audit or proof of every OS-service behavior. No external request is sent.

Fixtures are generated in memory with Core Text/Core Graphics, contain only synthetic phrases, and include a scanned PDF whose embedded string is independently checked to be empty. No real watched files are read. The main product target does not depend on the proof host.

## Passed cases

| Behavior | Observed evidence |
| --- | --- |
| UTF-8 / embedded PDF | Empty supported text is complete-empty; invalid UTF-8, unsupported formats, corrupt and password-locked PDF fixtures report unavailable; embedded PDF text requires no OCR |
| Image OCR | PNG, JPEG and locally encoded HEIC recognize the synthetic invoice phrase under direct-network denial |
| Scanned/mixed PDFs | Rasterized scanned page recognizes text; mixed PDF combines embedded and OCR origins; force mode records OCR origin even for a text-bearing page |
| TIFF | Both frames return their distinct phrases and page coverage |
| Raster budget | A 480,000-pixel PNG and scanned PDF still recognize text after downsampling into a 120,000-pixel test budget; default maximum is 20 megapixels |
| Recognition settings | Accurate automatic detection and Fast with explicit en-US pass; unsupported language is rejected rather than silently substituted; disabled OCR does not execute |
| Incomplete coverage | Page/text/input budgets and invalid limits are checked; truncation preserves valid UTF-8 and marks partial coverage |
| Deadline | A one-second budget on a 100-page mixed fixture returns partial with earlier embedded evidence retained; observed 1.03–1.04 seconds and 15–19 completed pages across runs |
| Cancellation | Pre-cancel and in-flight OCR cancel report canceled. Review found a missing UTF-8 completion check; a warmed 75-MiB Unicode stress check reproduced 4/4 missed overlapping cancellations before the fix and 0/4 afterward; equivalent XCTest regression passes |

The initial six extraction tests failed against the unavailable stub before implementation. The network-denied OCR proof then failed on the missing image OCR branch before the Vision implementation. Current full suite: 24 Rust tests passed; 15 native tests passed, one existing invalid-UTF-8 filesystem fixture skipped on this host. Read-only review verified the cancellation fix and reported no remaining blocker to the basic M1 OCR proof.

## Runtime language snapshot

The adapter pins `VNRecognizeTextRequestRevision3`, available on the deployment baseline, and queries supported languages separately for each recognition level. These are this host's advertised choices, not a hardcoded cross-OS promise or recognition-quality verification for every language. The OCR fixture text is English.

- Accurate (30): en-US, fr-FR, it-IT, de-DE, es-ES, pt-BR, zh-Hans, zh-Hant, yue-Hans, yue-Hant, ko-KR, ja-JP, ru-RU, uk-UA, th-TH, vi-VT, ar-SA, ars-SA, tr-TR, id-ID, cs-CZ, da-DK, nl-NL, no-NO, nn-NO, nb-NO, ms-MY, pl-PL, ro-RO, sv-SE.
- Fast (6): en-US, fr-FR, it-IT, de-DE, es-ES, pt-BR.

`vi-VT` is retained exactly as returned by the runtime. Automatic language detection uses Accurate; Fast requires explicit supported language selection. Language-correction support remains subject to the chosen language/OS.

## Evidence boundaries

Complete means the requested extraction source finished within its coverage limits; OCR accuracy is not guaranteed. Embedded-then-OCR processes PDF pages lacking usable embedded text. A page with some embedded text and a scanned region still requires force OCR to inspect the region. Incomplete text is not evidence of absence; the later Rust matcher must enforce the PRD's positive/negative/regex semantics.

Limits bound input acceptance, returned text, page/frame iteration and supplied raster area. PDFKit/ImageIO parsing and individual native drawing calls are not hard-preempted; cancellation/deadlines are cooperative between those calls and cancel an active Vision request. Full hostile/corrupt-document resource isolation, OS/language/format matrices, Intel/macOS 14 runtimes, engine queue/cancellation propagation, cache and full UI flows remain open tasks. The 1.8 feasibility proof does not complete tasks 4.2–4.4 or the full local-runtime acceptance gate.

Apple documents Vision processing as on-device, including offline use. API availability was checked against current primary documentation and installed headers; newer macOS-15-only `RecognizeTextRequest` APIs are not used. [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images), [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), [PDF page text](https://developer.apple.com/documentation/pdfkit/pdfpage/string), [PDF drawing transform](https://developer.apple.com/documentation/coregraphics/cgpdfpage/getdrawingtransform(_:rect:rotate:preserveaspectratio:))

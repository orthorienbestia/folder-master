## Purpose

Match local document contents and scanned images without uploading data, while exposing accuracy, coverage and resource-limit boundaries.

## ADDED Requirements

### Requirement: Defined local extraction formats
The app SHALL extract UTF-8 plain text and embedded PDF page text, and optionally recognize text from PNG, JPEG, TIFF, HEIC when locally decodable and scanned PDF pages. Unsupported/protected/corrupt files SHALL produce explicit statuses rather than fabricated empty text.

#### Scenario: Text PDF
- **WHEN** a PDF has readable embedded text and embedded-only mode is selected
- **THEN** matching uses extracted page text without OCR or source mutation

#### Scenario: Empty text versus unsupported file
- **WHEN** a supported empty text file or an unsupported binary is evaluated
- **THEN** the former can produce complete-empty text and the latter produces unavailable content

### Requirement: On-device OCR configuration
OCR SHALL operate offline, use runtime-supported language choices, and expose Accurate/Fast, automatic/ordered languages and supported language correction. Embedded-then-OCR SHALL process PDF pages lacking usable embedded text; force OCR SHALL process all relevant pages/frames.

#### Scenario: Mixed PDF
- **WHEN** a PDF contains text-bearing pages and scanned-only pages
- **THEN** embedded-then-OCR combines embedded extraction with local OCR for pages needing it

#### Scenario: Scanned region on text-bearing page
- **WHEN** a text-bearing page also contains an unrecognized scanned region
- **THEN** the user can select force OCR to inspect that region without an implicit completeness claim for embedded-only extraction

### Requirement: Bounded incomplete-content semantics
Extraction SHALL enforce the catalog's byte/page/text/time/raster limits, report completeness and process pages/frames incrementally. Positive literal substring evidence from partial extraction SHALL be usable; regex and negative text predicates SHALL require complete extraction.

#### Scenario: Page cap before sought text
- **WHEN** a PDF exceeds the page limit and no sought phrase is found in processed pages
- **THEN** absence remains Unknown, not true

#### Scenario: Positive evidence before timeout
- **WHEN** the required phrase is observed before extraction times out
- **THEN** a positive contains predicate can match with partial-evidence status visible

#### Scenario: Regex on truncated content
- **WHEN** a regex could appear to match an artificial end of truncated content
- **THEN** regex remains Unknown until complete extraction is available

### Requirement: Local cache privacy and invalidation
Persistent extracted-text cache SHALL be off by default, optional and bounded to seven days/100 MiB. Cache reuse SHALL invalidate on relevant file/extractor/settings changes and SHALL preserve incomplete statuses. Document text SHALL NOT enter history by default.

#### Scenario: OCR language changes
- **WHEN** selected OCR languages change
- **THEN** incompatible cached extraction is not reused as current evidence

#### Scenario: Clear content cache
- **WHEN** the user clears cached text
- **THEN** persisted extracted text is removed and stale in-flight results cannot repopulate the cleared cache without a fresh eligible request

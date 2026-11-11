import XCTest
import PDFKit

final class DocumentTextTests: XCTestCase {
    func testEmptyUTF8IsCompleteWhileInvalidOrUnsupportedBytesAreUnavailable() {
        let empty = DocumentText.extract(Data(), format: .utf8)
        XCTAssertEqual(empty.completeness, .complete)
        XCTAssertEqual(empty.text, "")
        let invalid = DocumentText.extract(Data([0xff, 0xfe]), format: .utf8)
        XCTAssertEqual(invalid.completeness, .unavailable)
        XCTAssertEqual(invalid.issues, [.invalidData])
        let unsupported = DocumentText.extract(Data("binary".utf8), format: .unsupported)
        XCTAssertEqual(unsupported.completeness, .unavailable)
        XCTAssertEqual(unsupported.issues, [.unsupportedFormat])
    }
    func testEmbeddedPDFExtractsTextWithoutOCRAndDoesNotRewriteInput() throws {
        let data = try ContentFixtures.pdf([.text("EMBEDDED ALPHA 7342")])
        let original = data
        let result = DocumentText.extract(data, format: .pdf)
        XCTAssertEqual(result.completeness, .complete)
        XCTAssertTrue(result.text.contains("EMBEDDED ALPHA 7342"))
        XCTAssertEqual(result.pages, [ContentPage(index: 0, origin: .embedded)])
        XCTAssertEqual(data, original)
    }
    func testPageCapRetainsEarlierEvidenceAndMarksCoverageIncomplete() throws {
        let data = try ContentFixtures.pdf([.text("FIRST PAGE"), .text("SECOND PAGE")])
        var options = ContentOptions(); options.limits.pages = 1
        let result = DocumentText.extract(data, format: .pdf, options: options)
        XCTAssertEqual(result.completeness, .partial)
        XCTAssertTrue(result.text.contains("FIRST PAGE"))
        XCTAssertFalse(result.text.contains("SECOND PAGE"))
        XCTAssertEqual(result.issues, [.pageLimit])
        XCTAssertEqual(result.totalPages, 2)
        XCTAssertEqual(result.pages.count, 1)
    }
    func testUTF8TextCapDoesNotSplitUnicodeScalarsOrClaimCompleteAbsence() {
        var options = ContentOptions(); options.limits.textBytes = 5
        let result = DocumentText.extract(Data("猫猫猫".utf8), format: .utf8, options: options)
        XCTAssertEqual(result.text, "猫")
        XCTAssertEqual(result.completeness, .partial)
        XCTAssertEqual(result.issues, [.textLimit])
    }
    func testInputLimitAndPreCancellationStopBeforeContentParsing() {
        var options = ContentOptions(); options.limits.inputBytes = 3
        let tooLarge = DocumentText.extract(Data("four".utf8), format: .utf8, options: options)
        XCTAssertEqual(tooLarge.completeness, .unavailable)
        XCTAssertEqual(tooLarge.issues, [.inputLimit])
        let cancellation = ContentCancellation(); cancellation.cancel()
        let canceled = DocumentText.extract(Data("valid".utf8), format: .utf8, cancellation: cancellation)
        XCTAssertEqual(canceled.completeness, .canceled)
        XCTAssertEqual(canceled.text, "")
        XCTAssertEqual(canceled.issues, [.canceled])
    }
    func testCorruptAndLockedPDFsAreNotInventedEmptyText() throws {
        let corrupt = DocumentText.extract(Data("not a PDF".utf8), format: .pdf)
        XCTAssertEqual(corrupt.completeness, .unavailable)
        XCTAssertEqual(corrupt.issues, [.invalidData])
        let protected = DocumentText.extract(try ContentFixtures.lockedPDF(), format: .pdf)
        XCTAssertEqual(protected.completeness, .unavailable)
        XCTAssertEqual(protected.issues, [.protectedPDF])
    }
    func testInvalidResourceBudgetsAreRejectedBeforeParsing() {
        for limits in [ContentLimits(inputBytes: 0), ContentLimits(pages: 0), ContentLimits(textBytes: 0),
                       ContentLimits(rasterPixels: 0), ContentLimits(timeoutSeconds: .nan)] {
            var options = ContentOptions(); options.limits = limits
            let result = DocumentText.extract(Data("valid".utf8), format: .utf8, options: options)
            XCTAssertEqual(result.completeness, .unavailable)
            XCTAssertEqual(result.issues, [.invalidOptions])
        }
    }
    func testImagesDoNotImplicitlyStartOCRInEmbeddedOnlyMode() throws {
        let image = try ContentFixtures.image("INVOICE ALPHA 7342")
        let result = DocumentText.extract(try ContentFixtures.encodedImages([image]), format: .image)
        XCTAssertEqual(result.completeness, .unavailable)
        XCTAssertEqual(result.issues, [.unsupportedFormat])
        XCTAssertTrue(result.pages.isEmpty)
    }
    func testCancellationDuringLargeUTF8CopyIsReflectedAtCompletion() {
        let bytes = Data(String(repeating: "猫", count: 25 * 1024 * 1024).utf8)
        var options = ContentOptions(); options.limits.textBytes = 50 * 1024 * 1024
        var baseline = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = DocumentText.extract(bytes, format: .utf8, options: options)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            withExtendedLifetime(result) {}
            baseline = min(baseline, elapsed)
        }
        var overlaps = 0
        for fraction in [0.3,0.5,0.7,0.9] {
            let cancellation = ContentCancellation(), timing = CancellationTiming(), delivered = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + baseline * fraction) {
                cancellation.cancel(); timing.record(); delivered.signal()
            }
            let result = DocumentText.extract(bytes, format: .utf8, options: options, cancellation: cancellation)
            let ended = DispatchTime.now().uptimeNanoseconds
            // Exclude the tiny return/cleanup race. This checks cancellations
            // delivered materially before extraction finishes, not after it.
            if let canceled = timing.read(), canceled + 5_000_000 < ended {
                overlaps += 1
                XCTAssertEqual(result.completeness, .canceled)
                XCTAssertTrue(result.issues.contains(.canceled))
            }
            delivered.wait()
        }
        XCTAssertGreaterThan(overlaps, 0, "No overlapping cancellation window was exercised")
    }
}

private final class CancellationTiming: @unchecked Sendable {
    private let lock = NSLock()
    private var time: UInt64?
    func record() { lock.lock(); time = DispatchTime.now().uptimeNanoseconds; lock.unlock() }
    func read() -> UInt64? { lock.lock(); defer { lock.unlock() }; return time }
}

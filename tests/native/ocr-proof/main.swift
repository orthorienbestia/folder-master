import Foundation
import PDFKit
import Darwin

func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "OCRProof", code: 1, userInfo: [NSLocalizedDescriptionKey:message]) }
}
func checkText(_ result: ContentResult, contains expected: String, label: String) throws {
    let normalized = result.text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    try expect(result.completeness == .complete && normalized.contains(expected), "\(label): \(result.completeness), \(result.issues), text=\(result.text)")
    print("OCR proof passed: \(label)")
}
func run() throws {
    guard CommandLine.arguments.count == 2, let port = UInt16(CommandLine.arguments[1]) else { throw NSError(domain: "OCRProof", code: 64) }
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    let networkError = errno
    try expect(connected < 0 && (networkError == EPERM || networkError == EACCES), "Proof process did not establish direct network denial")
    print("OCR proof network denied: errno \(networkError)")
    for quality in [OCRQuality.accurate, .fast] {
        let languages = try DocumentText.supportedLanguages(quality: quality)
        try expect(languages.contains("en-US"), "Fixture language is unavailable")
        let data = try JSONSerialization.data(withJSONObject: languages)
        print("Runtime \(quality) Vision revision 3 languages: \(String(decoding: data, as: UTF8.self))")
    }
    let image = try ContentFixtures.image("INVOICE ALPHA 7342")
    let scanned = try ContentFixtures.pdf([.scan(image)])
    let embedded = PDFDocument(data: scanned)?.string ?? ""
    try expect(embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Scanned PDF fixture unexpectedly has embedded text")
    var options = ContentOptions(); options.source = .embeddedThenOCR
    let png = try ContentFixtures.encodedImages([image])
    let pngResult = DocumentText.extract(png, format: .image, options: options)
    try checkText(pngResult, contains: "INVOICE ALPHA 7342", label: "PNG in network-denied process")
    try expect(pngResult.pages == [ContentPage(index: 0, origin: .ocr)], "PNG result origin is incorrect")
    let scanResult = DocumentText.extract(scanned, format: .pdf, options: options)
    try checkText(scanResult, contains: "INVOICE ALPHA 7342", label: "rasterized scanned PDF")
    try expect(scanResult.pages == [ContentPage(index: 0, origin: .ocr)], "Scanned PDF did not use OCR")
    let mixed = try ContentFixtures.pdf([.text("EMBEDDED FIRST PAGE"), .scan(image)])
    let mixedResult = DocumentText.extract(mixed, format: .pdf, options: options)
    try checkText(mixedResult, contains: "EMBEDDED FIRST PAGE", label: "mixed PDF embedded page")
    try checkText(mixedResult, contains: "INVOICE ALPHA 7342", label: "mixed PDF scanned page")
    try expect(mixedResult.pages == [ContentPage(index: 0, origin: .embedded), ContentPage(index: 1, origin: .ocr)], "Mixed PDF source routing is incorrect")
    options.source = .forceOCR
    let textPDF = try ContentFixtures.pdf([.text("FORCE OCR ALPHA 7342")])
    let forced = DocumentText.extract(textPDF, format: .pdf, options: options)
    try checkText(forced, contains: "FORCE OCR ALPHA 7342", label: "force OCR text-bearing PDF")
    try expect(forced.pages == [ContentPage(index: 0, origin: .ocr)], "Force OCR silently used embedded text")
    let jpeg = try ContentFixtures.encodedImages([image], type: .jpeg)
    try checkText(DocumentText.extract(jpeg, format: .image, options: options), contains: "INVOICE ALPHA 7342", label: "JPEG")
    if let heic = try? ContentFixtures.encodedImages([image], type: .heic) {
        try checkText(DocumentText.extract(heic, format: .image, options: options), contains: "INVOICE ALPHA 7342", label: "locally encoded HEIC")
    } else { print("HEIC fixture NOT RUN: local encoder unavailable") }
    let second = try ContentFixtures.image("SECOND BETA 9812")
    let tiff = try ContentFixtures.encodedImages([image, second], type: .tiff)
    let tiffResult = DocumentText.extract(tiff, format: .image, options: options)
    try checkText(tiffResult, contains: "INVOICE ALPHA 7342", label: "multipage TIFF first frame")
    try checkText(tiffResult, contains: "SECOND BETA 9812", label: "multipage TIFF second frame")
    try expect(tiffResult.pages.count == 2 && tiffResult.totalPages == 2, "TIFF frames were silently skipped")
    var bounded = options; bounded.limits.rasterPixels = 120_000
    try checkText(DocumentText.extract(png, format: .image, options: bounded), contains: "INVOICE ALPHA 7342", label: "downsampled PNG within smaller raster budget")
    try checkText(DocumentText.extract(scanned, format: .pdf, options: bounded), contains: "INVOICE ALPHA 7342", label: "downsampled PDF raster")
    options.quality = .fast; options.languages = []
    let unsupportedAuto = DocumentText.extract(png, format: .image, options: options)
    try expect(unsupportedAuto.completeness == .unavailable && unsupportedAuto.issues == [.unsupportedConfiguration], "Fast automatic language setting silently fell back")
    options.languages = ["en-US"]
    try checkText(DocumentText.extract(png, format: .image, options: options), contains: "INVOICE ALPHA 7342", label: "Fast with explicit language")
    options.languages = ["zz-ZZ"]
    let unknownLanguage = DocumentText.extract(png, format: .image, options: options)
    try expect(unknownLanguage.completeness != .complete && unknownLanguage.issues.contains(.unsupportedLanguage), "Unsupported language silently fell back")
    options.languages = ["en-US"]; options.ocrEnabled = false
    let disabled = DocumentText.extract(png, format: .image, options: options)
    try expect(disabled.completeness == .unavailable && disabled.issues == [.ocrDisabled], "Disabled OCR was executed or invented empty success")

    let longPDF = try ContentFixtures.pdf([.text("EARLY EVIDENCE ALPHA 7342")] + Array(repeating: FixturePage.scan(image), count: 99))
    var timed = ContentOptions(); timed.source = .embeddedThenOCR; timed.languages = ["en-US"]; timed.limits.timeoutSeconds = 1
    let started = DispatchTime.now().uptimeNanoseconds
    let incomplete = DocumentText.extract(longPDF, format: .pdf, options: timed)
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    try expect(incomplete.completeness == .partial && incomplete.issues.contains(.timedOut) && incomplete.pages.count < 100, "OCR deadline invented complete coverage")
    try expect(incomplete.text.contains("EARLY EVIDENCE ALPHA 7342"), "Deadline discarded earlier completed evidence")
    print("OCR proof passed: partial evidence retained after deadline (\(String(format: "%.2f", elapsed))s, \(incomplete.pages.count)/100 pages)")
    let cancellation = ContentCancellation()
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) { cancellation.cancel() }
    timed.limits.timeoutSeconds = 60
    let canceled = DocumentText.extract(longPDF, format: .pdf, options: timed, cancellation: cancellation)
    try expect(canceled.completeness == .canceled && canceled.issues.contains(.canceled) && canceled.pages.count < 100, "In-flight cancellation was not honored")
    print("OCR proof passed: in-flight cancellation")
    print("Local OCR proof completed without runtime network permission")
}
do { try run() }
catch { FileHandle.standardError.write(Data("OCR proof failed: \(error)\n".utf8)); exit(1) }

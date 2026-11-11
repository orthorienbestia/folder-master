import Foundation
import CoreGraphics
import PDFKit
import Vision
import ImageIO
import UniformTypeIdentifiers

enum ContentFormat { case utf8, pdf, image, unsupported }
enum ContentSource { case embeddedOnly, embeddedThenOCR, forceOCR }
enum OCRQuality { case accurate, fast }
enum ContentCompleteness: String, Codable { case complete, partial, unavailable, canceled }
enum ContentIssue: String, Codable, Error {
    case unsupportedFormat, invalidData, protectedPDF, inputLimit, pageLimit, textLimit
    case timedOut, canceled, ocrDisabled, unsupportedLanguage, unsupportedConfiguration
    case rasterizationFailed, recognitionFailed, invalidOptions
}
enum TextOrigin: String, Codable { case embedded, ocr }
struct ContentPage: Codable, Equatable {
    let index: Int
    let origin: TextOrigin
}
struct ContentResult: Codable {
    let text: String
    let completeness: ContentCompleteness
    let issues: [ContentIssue]
    let pages: [ContentPage]
    let totalPages: Int
}
struct ContentLimits {
    var inputBytes = 100 * 1024 * 1024
    var pages = 100
    var textBytes = 10 * 1024 * 1024
    var rasterPixels = 20_000_000
    var timeoutSeconds: Double = 60
}
struct ContentOptions {
    var source: ContentSource = .embeddedOnly
    var ocrEnabled = true
    var quality: OCRQuality = .accurate
    // Empty means automatic detection, supported in Accurate mode.
    var languages: [String] = []
    var languageCorrection = true
    var limits = ContentLimits()
}
final class ContentCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var isCanceled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// Synchronous worker API: callers must dispatch away from the UI actor. Bytes
// are supplied by the eligibility/file-access layer; this adapter opens no URL.
enum DocumentText {
    static func supportedLanguages(quality: OCRQuality) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = quality == .accurate ? .accurate : .fast
        return try request.supportedRecognitionLanguages()
    }
    static func extract(_ bytes: Data, format: ContentFormat, options: ContentOptions = ContentOptions(), cancellation: ContentCancellation = ContentCancellation()) -> ContentResult {
        if cancellation.isCanceled { return empty(.canceled, state: .canceled) }
        let limits = options.limits
        guard (1...1024 * 1024 * 1024).contains(limits.inputBytes), (1...1000).contains(limits.pages),
              (1...50 * 1024 * 1024).contains(limits.textBytes), (1...20_000_000).contains(limits.rasterPixels),
              limits.timeoutSeconds.isFinite, (1...600).contains(limits.timeoutSeconds) else { return empty(.invalidOptions) }
        guard bytes.count <= limits.inputBytes else { return empty(.inputLimit) }
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(limits.timeoutSeconds * 1_000_000_000)
        switch format {
        case .unsupported: return empty(.unsupportedFormat)
        case .utf8:
            guard let string = String(data: bytes, encoding: .utf8) else { return empty(.invalidData) }
            var result = Accumulator(totalPages: 1, limit: limits.textBytes)
            if let issue = interruption(cancellation, deadline: deadline) { result.note(issue); return result.result }
            _ = result.append(string, index: 0, origin: .embedded)
            if let issue = interruption(cancellation, deadline: deadline) { result.note(issue) }
            return result.result
        case .pdf:
            guard let document = PDFDocument(data: bytes) else { return empty(.invalidData) }
            guard !document.isLocked, document.allowsCopying else { return empty(.protectedPDF) }
            var result = Accumulator(totalPages: document.pageCount, limit: limits.textBytes)
            if document.pageCount > limits.pages { result.note(.pageLimit) }
            for index in 0..<min(document.pageCount, limits.pages) {
                if let issue = interruption(cancellation, deadline: deadline) { result.note(issue); break }
                let keepGoing = autoreleasepool { () -> Bool in
                    guard let page = document.page(at: index) else { result.note(.invalidData); return true }
                    let embedded = page.string ?? ""
                    if options.source == .embeddedOnly || (options.source == .embeddedThenOCR && !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        return result.append(embedded, index: index, origin: .embedded)
                    }
                    guard options.ocrEnabled else { result.note(.ocrDisabled); return true }
                    guard let image = rasterize(page: page, pixelLimit: limits.rasterPixels) else { result.note(.rasterizationFailed); return true }
                    switch recognize(image, options: options, cancellation: cancellation, deadline: deadline) {
                    case .success(let text): return result.append(text, index: index, origin: .ocr)
                    case .failure(let issue): result.note(issue); return issue != .canceled && issue != .timedOut
                    }
                }
                if !keepGoing { break }
            }
            if let issue = interruption(cancellation, deadline: deadline) { result.note(issue) }
            return result.result
        case .image:
            guard options.source != .embeddedOnly else { return empty(.unsupportedFormat) }
            guard options.ocrEnabled else { return empty(.ocrDisabled) }
            guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache as String:false] as CFDictionary),
                  let type = CGImageSourceGetType(source) else { return empty(.invalidData) }
            let allowed = [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier]
            guard allowed.contains(type as String) else { return empty(.unsupportedFormat) }
            let count = CGImageSourceGetCount(source)
            guard count > 0 else { return empty(.invalidData) }
            var result = Accumulator(totalPages: count, limit: limits.textBytes)
            if count > limits.pages { result.note(.pageLimit) }
            for index in 0..<min(count, limits.pages) {
                if let issue = interruption(cancellation, deadline: deadline) { result.note(issue); break }
                let keepGoing = autoreleasepool { () -> Bool in
                    guard let image = thumbnail(source: source, index: index, pixelLimit: limits.rasterPixels) else { result.note(.rasterizationFailed); return true }
                    switch recognize(image, options: options, cancellation: cancellation, deadline: deadline) {
                    case .success(let text): return result.append(text, index: index, origin: .ocr)
                    case .failure(let issue): result.note(issue); return issue != .canceled && issue != .timedOut
                    }
                }
                if !keepGoing { break }
            }
            if let issue = interruption(cancellation, deadline: deadline) { result.note(issue) }
            return result.result
        }
    }

    private static func recognize(_ image: CGImage, options: ContentOptions, cancellation: ContentCancellation, deadline: UInt64) -> Result<String,ContentIssue> {
        if let issue = interruption(cancellation, deadline: deadline) { return .failure(issue) }
        guard options.quality != .fast || !options.languages.isEmpty else { return .failure(.unsupportedConfiguration) }
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = options.quality == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = options.languageCorrection
        request.automaticallyDetectsLanguage = options.languages.isEmpty
        do {
            let supported = Set(try request.supportedRecognitionLanguages())
            guard options.languages.allSatisfy({ supported.contains($0) }) else { return .failure(.unsupportedLanguage) }
            if !options.languages.isEmpty { request.recognitionLanguages = options.languages }
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
            timer.setEventHandler {
                if cancellation.isCanceled || DispatchTime.now().uptimeNanoseconds >= deadline { request.cancel() }
            }
            timer.activate()
            defer { timer.setEventHandler {}; timer.cancel() }
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            if let issue = interruption(cancellation, deadline: deadline) { return .failure(issue) }
            return .success((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
        } catch {
            return .failure(interruption(cancellation, deadline: deadline) ?? .recognitionFailed)
        }
    }

    private static func dimensions(width: Double, height: Double, preferredScale: Double, pixelLimit: Int) -> (Int,Int)? {
        let area = width * height
        guard width.isFinite, height.isFinite, area.isFinite, width > 0, height > 0, area > 0 else { return nil }
        // The edge bound also handles extremely thin, huge PDF media boxes
        // whose short edge rounds up to one pixel after area-based scaling.
        let scale = min(preferredScale, sqrt(Double(pixelLimit) / area), Double(pixelLimit) / max(width, height))
        let w = max(1, Int(floor(width * scale))), h = max(1, Int(floor(height * scale)))
        guard w <= pixelLimit, h <= pixelLimit, w * h <= pixelLimit else { return nil }
        return (w,h)
    }
    private static func rasterize(page: PDFPage, pixelLimit: Int) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let box = reference.getBoxRect(.mediaBox)
        let rotated = abs(reference.rotationAngle % 180) == 90
        let width = Double(rotated ? box.height : box.width), height = Double(rotated ? box.width : box.height)
        guard let (w,h) = dimensions(width: width, height: height, preferredScale: 2, pixelLimit: pixelLimit),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let target = CGRect(x: 0, y: 0, width: w, height: h)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(target)
        context.concatenate(reference.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        return context.makeImage()
    }
    private static func thumbnail(source: CGImageSource, index: Int, pixelLimit: Int) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String:Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber,
              let (w,h) = dimensions(width: width.doubleValue, height: height.doubleValue, preferredScale: 1, pixelLimit: pixelLimit) else { return nil }
        var edge = max(w,h)
        for _ in 0..<3 {
            let settings: [String:Any] = [kCGImageSourceCreateThumbnailFromImageAlways as String:true,
                kCGImageSourceCreateThumbnailWithTransform as String:true,
                kCGImageSourceShouldCacheImmediately as String:true,
                kCGImageSourceThumbnailMaxPixelSize as String:edge]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, settings as CFDictionary) else { return nil }
            let area = Double(image.width) * Double(image.height)
            if area <= Double(pixelLimit) { return image }
            // ImageIO may round the short edge upward. Retry smaller instead
            // of passing an over-budget raster to Vision.
            edge = max(1, Int(Double(edge) * sqrt(Double(pixelLimit) / area)) - 1)
        }
        return nil
    }
    private static func empty(_ issue: ContentIssue, state: ContentCompleteness = .unavailable) -> ContentResult {
        ContentResult(text: "", completeness: state, issues: [issue], pages: [], totalPages: 0)
    }
    private static func interruption(_ cancellation: ContentCancellation, deadline: UInt64) -> ContentIssue? {
        if cancellation.isCanceled { return .canceled }
        return DispatchTime.now().uptimeNanoseconds >= deadline ? .timedOut : nil
    }
    private struct Accumulator {
        let totalPages: Int
        let limit: Int
        var text = ""
        var pages: [ContentPage] = []
        var issues: [ContentIssue] = []
        var completeness: ContentCompleteness = .complete
        mutating func note(_ issue: ContentIssue) {
            if !issues.contains(issue) { issues.append(issue) }
            if issue == .canceled { completeness = .canceled }
            else if completeness != .canceled { completeness = .partial }
        }
        mutating func append(_ string: String, index: Int, origin: TextOrigin) -> Bool {
            pages.append(ContentPage(index: index, origin: origin))
            let fragment = text.isEmpty || string.isEmpty ? string : "\n" + string
            let room = max(0, limit - text.utf8.count)
            if fragment.utf8.count <= room { text += fragment; return true }
            var prefix = Data(fragment.utf8.prefix(room))
            while !prefix.isEmpty && String(data: prefix, encoding: .utf8) == nil { prefix.removeLast() }
            text += String(data: prefix, encoding: .utf8) ?? ""
            note(.textLimit)
            return false
        }
        var result: ContentResult {
            let unavailable = pages.isEmpty && issues.contains { [.invalidData, .ocrDisabled, .unsupportedLanguage, .unsupportedConfiguration, .rasterizationFailed, .recognitionFailed].contains($0) }
            let state: ContentCompleteness = completeness == .partial && unavailable ? .unavailable : completeness
            return ContentResult(text: text, completeness: state, issues: issues, pages: pages, totalPages: totalPages)
        }
    }
}

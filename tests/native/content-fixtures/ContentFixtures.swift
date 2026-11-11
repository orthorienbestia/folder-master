import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum FixturePage { case text(String), scan(CGImage) }
enum ContentFixtures {
    static func image(_ text: String) throws -> CGImage {
        guard let context = CGContext(data: nil, width: 1200, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw error() }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 400))
        draw(text, in: context, at: CGPoint(x: 55, y: 180), size: 64)
        guard let image = context.makeImage() else { throw error() }
        return image
    }
    static func encodedImages(_ images: [CGImage], type: UTType = .png) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil) else { throw error() }
        for image in images { CGImageDestinationAddImage(destination, image, nil) }
        guard CGImageDestinationFinalize(destination) else { throw error() }
        return data as Data
    }
    static func pdf(_ pages: [FixturePage]) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 900, height: 400)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw error() }
        for page in pages {
            context.beginPDFPage(nil)
            switch page {
            case .text(let text): draw(text, in: context, at: CGPoint(x: 45, y: 180), size: 40)
            case .scan(let image): context.draw(image, in: box)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
    static func lockedPDF() throws -> Data {
        let input = try pdf([.text("PROTECTED ALPHA")])
        guard let document = PDFDocument(data: input), let output = document.dataRepresentation(options: [PDFDocumentWriteOption.userPasswordOption:"fixture-password", PDFDocumentWriteOption.ownerPasswordOption:"fixture-owner"]) else { throw error() }
        return output
    }
    private static func draw(_ text: String, in context: CGContext, at point: CGPoint, size: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String):font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray: 0, alpha: 1)])
        context.textMatrix = .identity; context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }
    private static func error() -> NSError { NSError(domain: "ContentFixture", code: 1) }
}

import UniformTypeIdentifiers
import XCTest

final class KindMetadataTests: XCTestCase {
    func testPlatformCategoriesPermitDocumentPDFOverlapWithoutTreatingImagesAsDocuments() throws {
        let pdf = try XCTUnwrap(NativeKindFacts.observe(.pdf))
        XCTAssertEqual(pdf.categories, [.document, .pdf])
        XCTAssertEqual(pdf.identifier, UTType.pdf.identifier)
        XCTAssertEqual(try XCTUnwrap(NativeKindFacts.observe(.jpeg)).categories, [.image])
        XCTAssertEqual(try XCTUnwrap(NativeKindFacts.observe(.movie)).categories, [.video])
        XCTAssertEqual(try XCTUnwrap(NativeKindFacts.observe(.audio)).categories, [.audio])
        XCTAssertEqual(try XCTUnwrap(NativeKindFacts.observe(.archive)).categories, [.archive])
        for type in [UTType.text, .compositeContent, .spreadsheet, .presentation] {
            XCTAssertTrue(try XCTUnwrap(NativeKindFacts.observe(type)).categories.contains(.document))
        }
    }
    func testMissingTypeDiffersFromKnownOther() throws {
        XCTAssertNil(NativeKindFacts.observe(nil))
        let other = try XCTUnwrap(NativeKindFacts.observe(.data))
        XCTAssertTrue(other.categories.isEmpty)
        XCTAssertEqual(other.identifier, UTType.data.identifier)
    }
    func testCustomConformancePreservesUnsupportedAnswersInWireData() throws {
        let unknown = "com.foldermaster.unregistered." + UUID().uuidString.lowercased()
        let facts = try XCTUnwrap(
            NativeKindFacts.observe(.jpeg, customTypes: ["public.image", "public.audio", unknown, "public.image"]))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(facts)) as! [String: Any]
        let answers = object["custom_conformance"] as! [String: Any]
        XCTAssertEqual(answers["public.image"] as? Bool, true)
        XCTAssertEqual(answers["public.audio"] as? Bool, false)
        XCTAssertTrue(answers[unknown] is NSNull)
        XCTAssertEqual(answers.count, 3)
        XCTAssertEqual(Set(object["categories"] as! [String]), ["image"])
    }
}

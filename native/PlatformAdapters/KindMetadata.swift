import Foundation
import UniformTypeIdentifiers

enum NativeKindCategory: String, Codable, Hashable {
    case document, image, pdf, audio, video, archive
}

/// Facts about an already-observed platform type; no path lookup or file read.
struct NativeKindFacts: Codable {
    let identifier: String
    let categories: Set<NativeKindCategory>
    let custom_conformance: [String: Bool?]

    static func observe(_ type: UTType?, customTypes: [String] = []) -> Self? {
        guard let type else { return nil }
        var categories = Set<NativeKindCategory>()
        if [UTType.text, .compositeContent, .spreadsheet, .presentation, .pdf].contains(where: { type.conforms(to: $0) }
        ) {
            categories.insert(.document)
        }
        for (category, base) in [
            (NativeKindCategory.image, UTType.image), (.pdf, .pdf), (.audio, .audio), (.video, .movie),
            (.archive, .archive),
        ] {
            if type.conforms(to: base) { categories.insert(category) }
        }
        var answers: [String: Bool?] = [:]
        for identifier in Set(customTypes) {
            let answer = UTType(identifier).map { type.conforms(to: $0) }
            // Subscript assignment of nil would erase the unsupported answer.
            // Keep a present null so it cannot become a negative match.
            answers.updateValue(answer, forKey: identifier)
        }
        return Self(identifier: type.identifier, categories: categories, custom_conformance: answers)
    }
}

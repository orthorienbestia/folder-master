import Foundation
import Security

// Feasibility protocol only. This is not connected to the app's rule executor.
@objc protocol ScriptProofProtocol {
    func execute(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

struct ScriptProofRequest: Codable {
    let version: Int
    let script: Data
    let input: Data
    let metadata: Data
    let arguments: [String]
    let timeoutSeconds: Int
}

struct ScriptProofOutput: Codable {
    let name: String
    let bytes: Data
}

struct ScriptProofReply: Codable {
    let status: String
    let message: String
    let exitCode: Int32?
    let log: Data
    let outputs: [ScriptProofOutput]
}

enum ProofSigning {
    static func requirement(at url: URL) throws -> String {
        var code: SecStaticCode?
        try check(SecStaticCodeCreateWithPath(url as CFURL, [], &code))
        guard let code else { throw failure("Missing static code") }
        try check(SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil))
        var requirement: SecRequirement?
        try check(SecCodeCopyDesignatedRequirement(code, [], &requirement))
        guard let requirement else { throw failure("Missing designated requirement") }
        var text: CFString?
        try check(SecRequirementCopyString(requirement, [], &text))
        guard let text else { throw failure("Missing requirement string") }
        return text as String
    }
    private static func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "FolderMaster.ScriptProof", code: 1, userInfo: [NSLocalizedDescriptionKey:text]) }
}

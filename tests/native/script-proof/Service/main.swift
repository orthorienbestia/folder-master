import Foundation

final class ScriptProofService: NSObject, ScriptProofProtocol {
    func execute(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        let result = StagedRunner.execute(request)
        reply(try! JSONEncoder().encode(result))
    }
}

final class ProofListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        // Ad-hoc feasibility proof only. This is not a spoof-resistant release
        // client anchor; the product service must additionally pin our Team ID.
        connection.setCodeSigningRequirement("identifier \"local.foldermaster.script-proof\"")
        connection.exportedInterface = NSXPCInterface(with: ScriptProofProtocol.self)
        connection.exportedObject = ScriptProofService()
        connection.activate()
        return true
    }
}

let delegate = ProofListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

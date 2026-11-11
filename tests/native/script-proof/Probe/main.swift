import Foundation

guard CommandLine.arguments.count == 2, let port = UInt16(CommandLine.arguments[1]) else { exit(64) }
let observed = IsolationProbe.observe(port: port)
let encoded = try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys])
FileHandle.standardOutput.write(encoded)

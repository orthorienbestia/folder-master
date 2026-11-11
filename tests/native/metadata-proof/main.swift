import Foundation
import CryptoKit
import Darwin

// Standalone M1 feasibility harness. It creates and mutates only its own fixtures.
// No production action executor, staging/publication protocol or UI calls this.
struct ProofFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw ProofFailure(message) }
}
func posix(_ operation: String) -> ProofFailure { ProofFailure("\(operation): errno \(errno) (\(String(cString: strerror(errno))))") }
func setAttribute(_ name: String, _ data: Data, at url: URL) throws {
    let result = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, 0) }
    guard result == 0 else { throw posix("setxattr \(name)") }
}
func attributes(at url: URL) throws -> [String: Data] {
    let count = listxattr(url.path, nil, 0, 0)
    guard count >= 0 else { throw posix("listxattr") }
    if count == 0 { return [:] }
    var names = [CChar](repeating: 0, count: count)
    let actual = listxattr(url.path, &names, names.count, 0)
    guard actual == count else { throw ProofFailure("xattr list changed during fixture read") }
    let raw = names.map { UInt8(bitPattern: $0) }
    var result: [String: Data] = [:]
    for bytes in raw.split(separator: 0) {
        let name = String(decoding: bytes, as: UTF8.self)
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size >= 0 else { throw posix("getxattr size \(name)") }
        var data = Data(count: size)
        let actual = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, 0) }
        guard actual == size else { throw ProofFailure("xattr \(name) changed during fixture read") }
        result[name] = data
    }
    return result
}
struct Snapshot: Equatable {
    let hash: String
    let bytes: Int
    let tags: [String]?
    let label: Int?
    let xattrs: [String: Data]
    let mode: UInt16
    let device: Int32
    let inode: UInt64
    let modificationSeconds: Int
    let modificationNanoseconds: Int
    var summary: [String: Any] {
        ["sha256": hash, "bytes": bytes, "tags": tags as Any? ?? NSNull(), "label": label as Any? ?? NSNull(),
         "xattrs": xattrs.mapValues { ["bytes": $0.count, "sha256": SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()] },
         "mode": String(mode, radix: 8), "device": device, "inode": inode,
         "mtimeSeconds": modificationSeconds, "mtimeNanoseconds": modificationNanoseconds]
    }
}
func snapshot(_ url: URL) throws -> Snapshot {
    // URL resource values cache: construct a new URL for every post-write read.
    let fresh = URL(fileURLWithPath: url.path)
    let values = try fresh.resourceValues(forKeys: [.tagNamesKey, .labelNumberKey])
    let data = try Data(contentsOf: fresh)
    var info = stat()
    guard lstat(fresh.path, &info) == 0 else { throw posix("lstat") }
    return try Snapshot(hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), bytes: data.count,
                        tags: values.tagNames?.sorted(), label: values.labelNumber, xattrs: attributes(at: fresh),
                        mode: info.st_mode & 0o7777, device: info.st_dev, inode: info.st_ino,
                        modificationSeconds: info.st_mtimespec.tv_sec, modificationNanoseconds: info.st_mtimespec.tv_nsec)
}
func update(_ url: URL, tags: [String]? = nil, label: Int? = nil) throws {
    // The Swift tagNames setter requires macOS 26 in the current SDK.
    // The older Foundation NSURL resource-key API supports the macOS 14 target.
    let fresh = NSURL(fileURLWithPath: url.path)
    var values: [URLResourceKey: Any] = [:]
    if let tags { values[.tagNamesKey] = tags }
    if let label { values[.labelNumberKey] = label }
    try fresh.setResourceValues(values)
}
func verifyCopy(_ source: Snapshot, _ destination: Snapshot, crossVolume: Bool) throws {
    try require(source.bytes == destination.bytes && source.hash == destination.hash, "copied bytes differ")
    try require(source.tags == destination.tags && source.label == destination.label, "copied Finder values differ")
    let regularSource = source.xattrs.filter { $0.key != "com.apple.quarantine" }
    let regularDestination = destination.xattrs.filter { $0.key != "com.apple.quarantine" }
    try require(regularSource == regularDestination, "non-quarantine xattr bytes differ")
    try require(destination.xattrs["com.apple.quarantine"]?.isEmpty == false, "system quarantine was lost")
    try require(source.mode == destination.mode, "copied permission mode differs")
    try require(source.modificationSeconds == destination.modificationSeconds && source.modificationNanoseconds == destination.modificationNanoseconds, "copied modification time differs")
    try require(crossVolume ? source.device != destination.device : source.device == destination.device, "volume identity does not match test case")
    try require(source.device != destination.device || source.inode != destination.inode, "copy reused source identity")
}
func performCopy(_ method: String, from source: URL, to destination: URL) throws {
    switch method {
    case "Foundation.copyItem": try FileManager.default.copyItem(at: source, to: destination)
    case "copyfile.ALL_EXCL":
        guard copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_EXCL)) == 0 else { throw posix("copyfile") }
    default: throw ProofFailure("unknown proof method")
    }
}

var report: [String: Any] = ["scope": "generated regular-file fixtures only", "os": ProcessInfo.processInfo.operatingSystemVersionString, "observedAt": ISO8601DateFormatter().string(from: Date())]
var owned: [URL] = []
do {
    guard CommandLine.arguments.count == 3 else { throw ProofFailure("Usage: metadata-proof LOCAL_PARENT SECOND_VOLUME_PARENT") }
    let parents = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    var volumes: [[String: Any]] = []
    for (index, parent) in parents.enumerated() {
        let volume = try parent.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIdentifierKey, .volumeNameKey])
        try require(volume.volumeIsLocal == true, "fixture parent is not a verified local volume")
        var fs = statfs()
        guard statfs(parent.path, &fs) == 0 else { throw posix("statfs") }
        let type = withUnsafePointer(to: &fs.f_fstypename) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        volumes.append(["index": index, "nativeLocal": true, "filesystem": type])
    }
    report["volumes"] = volumes
    let token = "FolderMasterMetadata-\(UUID().uuidString)"
    for parent in parents {
        let root = parent.appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        owned.append(root)
    }
    defer { for root in owned.reversed() { try? FileManager.default.removeItem(at: root) } }
    let payload = Data((0..<(256 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    var sources: [(URL, Snapshot)] = []
    var transitionsByVolume: [[String: Any]] = []
    for (volumeIndex, root) in owned.enumerated() {
        let source = root.appendingPathComponent("source.bin")
        try payload.write(to: source, options: .withoutOverwriting)
        var transitions: [[String: Any]] = []
        let mutations: [(String, [String]?, Int?)] = [
            ("add plain tag", ["FolderMasterPlain"], nil),
            ("set Red label 6, leave tags", nil, 6),
            ("clear nonzero label, leave plain tag", nil, 0),
            ("restore Red label, leave plain tag", nil, 6),
            ("replace with plain tag, leave label", ["FolderMasterReplacement"], nil),
            ("clear label 0, leave tags", nil, 0),
            ("replace with named Red tag, leave label", ["Red"], nil),
            ("remove all tags, leave label", [], nil),
            ("set Blue label 4, leave tags", nil, 4),
            ("set tags and Red label in one resource-values write", ["FolderMasterFixture", "Red"], 6),
            ("set final Red label separately", nil, 6)
        ]
        for (name, tags, label) in mutations {
            let before = try snapshot(source)
            try update(source, tags: tags, label: label)
            let after = try snapshot(source)
            if let label, tags == nil { try require(after.label == label, "requested label did not roundtrip: \(name)") }
            // Record actual tags even when the platform adds/removes related colors.
            if let tags, !tags.isEmpty {
                try require(Set(tags).isSubset(of: Set(after.tags ?? [])), "requested tags did not roundtrip: \(name)")
            }
            if tags == ["FolderMasterReplacement"] {
                try require(after.tags?.contains("FolderMasterPlain") != true, "replaced plain tag was retained")
            }
            if tags?.isEmpty == true {
                // Preserve raw nil in the report: this checks that no tag is
                // reported after removal, not that nil is known-empty metadata.
                try require(after.tags?.isEmpty != false && after.label == 0, "clear tags retained reported tags or color label")
            }
            try require(after.hash == before.hash, "metadata write changed file bytes")
            transitions.append(["operation": name, "requestedTags": tags as Any? ?? NSNull(), "requestedLabel": label as Any? ?? NSNull(), "before": before.summary, "after": after.summary])
        }
        try setAttribute("com.foldermaster.metadata-proof", Data([0, 1, 127, 128, 255]), at: source)
        try setAttribute("com.apple.ResourceFork", Data("Synthetic resource fork\u{0}with bytes\u{ff}".utf8), at: source)
        try setAttribute("com.apple.quarantine", Data("0081;6553f100;FolderMasterMetadataProof;00000000-0000-0000-0000-000000000001".utf8), at: source)
        guard chmod(source.path, 0o640) == 0 else { throw posix("chmod") }
        var times = [timespec(tv_sec: 1_700_000_000, tv_nsec: 123_456_789), timespec(tv_sec: 1_700_000_000, tv_nsec: 987_654_321)]
        guard utimensat(AT_FDCWD, source.path, &times, 0) == 0 else { throw posix("utimensat") }
        let baseline = try snapshot(source)
        try require(baseline.xattrs["com.apple.ResourceFork"] != nil && baseline.xattrs["com.apple.quarantine"] != nil, "required fixture metadata was not created")
        sources.append((source, baseline))
        transitionsByVolume.append(["volumeIndex": volumeIndex, "device": baseline.device, "transitions": transitions])
    }
    try require(sources[0].1.device != sources[1].1.device, "parents must be distinct local volumes")
    var copies: [[String: Any]] = []
    for (sourceIndex, item) in sources.enumerated() {
        let (source, baseline) = item
        for (index, root) in owned.enumerated() {
            for method in ["Foundation.copyItem", "copyfile.ALL_EXCL"] {
                let destination = root.appendingPathComponent("from-\(sourceIndex)-" + method + ".bin")
                try performCopy(method, from: source, to: destination)
                let copied = try snapshot(destination)
                try verifyCopy(baseline, copied, crossVolume: index != sourceIndex)
                let beforeConflict = try snapshot(destination)
                var refused = false
                do { try performCopy(method, from: source, to: destination) } catch { refused = true }
                try require(refused, "existing fixture destination was not rejected")
                try require(try snapshot(destination) == beforeConflict, "destination changed after conflict")
                try require(try snapshot(source) == baseline, "source changed after copy")
                copies.append(["method": method, "sourceVolumeIndex": sourceIndex, "destinationVolumeIndex": index, "crossVolume": index != sourceIndex, "result": "passed", "existingDestination": "rejected and unchanged", "sourceUnchanged": true, "allXattrsByteIdentical": baseline.xattrs == copied.xattrs,
                               "quarantineSource": String(decoding: baseline.xattrs["com.apple.quarantine"]!, as: UTF8.self),
                               "quarantineDestination": String(decoding: copied.xattrs["com.apple.quarantine"]!, as: UTF8.self),
                               "destination": copied.summary])
            }
        }
    }
    report["transitionsByVolume"] = transitionsByVolume
    report["sources"] = sources.map { $0.1.summary }
    report["copies"] = copies
    report["result"] = "passed"
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    for root in owned.reversed() { try? FileManager.default.removeItem(at: root) }
    fputs("METADATA PROOF FAILED: \(error)\n", stderr)
    exit(1)
}

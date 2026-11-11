import Foundation
import Darwin
import CoreFoundation

struct StoredFolder: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var display_name: String
    var path_bytes_base64: String
    var bookmark_base64: String
    var identity: String
    var enabled: Bool
    var recursive: Bool
    var include_hidden: Bool
    var exclusions: [String]
    var watch_mode: String
    var poll_interval_seconds: UInt32
    var revision: UInt64
}

struct FolderCandidate: Sendable {
    let name: String
    let path: Data
    let bookmark: Data
}

enum FolderAccessError: LocalizedError {
    case invalidFolder, remoteVolume, unavailable, package
    var errorDescription: String? {
        switch self {
        case .invalidFolder: return "Choose a real local folder, rather than a file, alias or symbolic link."
        case .remoteVolume: return "Only folders on local mounted volumes are supported."
        case .unavailable: return "The folder is unavailable or access was denied. Reconnect it or choose another folder."
        case .package: return "Choose a regular folder rather than an app or document package."
        }
    }
}

enum NativeFolderAccess {
    static func candidate(for url: URL) throws -> FolderCandidate {
        guard url.isFileURL else { throw FolderAccessError.invalidFolder }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey, .isPackageKey, .volumeIsLocalKey])
        guard values.isDirectory == true, values.isAliasFile != true, values.isSymbolicLink != true else { throw FolderAccessError.invalidFolder }
        guard values.isPackage != true else { throw FolderAccessError.package }
        guard values.volumeIsLocal == true else { throw FolderAccessError.remoteVolume }
        let readable = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else { return false }
            return Darwin.access(pointer, R_OK | X_OK) == 0
        }
        guard readable else { throw FolderAccessError.unavailable }
        let canonicalBytes = try url.withUnsafeFileSystemRepresentation { input -> Data in
            guard let input, let resolved = Darwin.realpath(input, nil) else { throw FolderAccessError.unavailable }
            defer { Darwin.free(resolved) }
            return Data(bytes: resolved, count: strlen(resolved))
        }
        let canonical = try Self.url(for: canonicalBytes)
        let bookmark = try canonical.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return FolderCandidate(name: canonical.lastPathComponent, path: try pathData(for: canonical), bookmark: bookmark)
    }
    static func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .volumeIsLocalKey])
        guard values.isDirectory == true else { throw FolderAccessError.unavailable }
        guard values.volumeIsLocal == true else { throw FolderAccessError.remoteVolume }
        return url
    }
    static func pathData(for url: URL) throws -> Data {
        guard url.isFileURL else { throw FolderAccessError.invalidFolder }
        return try url.withUnsafeFileSystemRepresentation { pointer -> Data in
            guard let pointer else { throw FolderAccessError.invalidFolder }
            return Data(bytes: pointer, count: strlen(pointer))
        }
    }
    static func url(for bytes: Data) throws -> URL {
        guard !bytes.isEmpty, bytes.first == 47, !bytes.contains(0), bytes.count <= 32768 else { throw FolderAccessError.invalidFolder }
        let location = bytes.withUnsafeBytes { memory in
            CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, memory.bindMemory(to: UInt8.self).baseAddress!, memory.count, false)
        }
        guard let location else { throw FolderAccessError.invalidFolder }
        // Preserve Core Foundation's raw filesystem bytes. Swift's direct
        // file-URL constructor replaces invalid UTF-8 before this boundary.
        return location as URL
    }
}

extension StoredFolder {
    var fileURL: URL? {
        guard let bytes = Data(base64Encoded: path_bytes_base64) else { return nil }
        return try? NativeFolderAccess.url(for: bytes)
    }
}

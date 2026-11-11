import XCTest
import Darwin

final class FolderAccessTests: XCTestCase {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("folder-master-access-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func testLocalDirectoryBookmarkTracksRenameWithoutChangingContents() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: false)
        let file = inbox.appendingPathComponent("untouched.txt")
        try Data("untouched".utf8).write(to: file)
        let candidate = try NativeFolderAccess.candidate(for: inbox)
        XCTAssertEqual(candidate.name, "Inbox")
        XCTAssertEqual(try NativeFolderAccess.url(for: candidate.path).standardizedFileURL, inbox.standardizedFileURL)
        let renamed = root.appendingPathComponent("Renamed", isDirectory: true)
        try FileManager.default.moveItem(at: inbox, to: renamed)
        XCTAssertEqual(try NativeFolderAccess.resolve(candidate.bookmark).resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: renamed.appendingPathComponent("untouched.txt")), Data("untouched".utf8))
    }

    func testFilesLinksPackagesAndNonFileURLsCannotEnrollAsFolders() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file.txt"); try Data().write(to: file)
        let link = root.appendingPathComponent("alias"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let package = root.appendingPathComponent("Example.app", isDirectory: true); try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        XCTAssertThrowsError(try NativeFolderAccess.candidate(for: file))
        XCTAssertThrowsError(try NativeFolderAccess.candidate(for: link))
        XCTAssertThrowsError(try NativeFolderAccess.candidate(for: package))
        XCTAssertThrowsError(try NativeFolderAccess.candidate(for: URL(string: "https://example.invalid")!))
    }

    func testRawPathBytesRoundTripWithoutLossyStringConversion() throws {
        let bytes = Data([47,116,109,112,47,255,46,112,100,102])
        XCTAssertEqual(try NativeFolderAccess.pathData(for: NativeFolderAccess.url(for: bytes)), bytes)
        XCTAssertThrowsError(try NativeFolderAccess.url(for: Data([47,0,120])))
        XCTAssertThrowsError(try NativeFolderAccess.url(for: Data("relative/path".utf8)))
    }

    func testEnrollmentPreservesActualNonUTF8DirectoryName() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var prefix = try NativeFolderAccess.pathData(for: root.resolvingSymlinksInPath())
        while prefix.last == 47 { prefix.removeLast() }
        let raw = prefix + Data([47,255])
        let chars = raw.map { CChar(bitPattern: $0) } + [0]
        let result = chars.withUnsafeBufferPointer { Darwin.mkdir($0.baseAddress!, 0o700) }
        if result != 0 && errno == EILSEQ {
            throw XCTSkip("The fixture volume rejects non-UTF-8 directory names (EILSEQ). Raw URL bytes are covered separately.")
        }
        XCTAssertEqual(result, 0)
        guard result == 0 else { return }
        let candidate = try NativeFolderAccess.candidate(for: NativeFolderAccess.url(for: raw))
        XCTAssertEqual(candidate.path, raw)
    }
}

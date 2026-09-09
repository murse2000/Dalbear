import XCTest
@testable import FolderCore

final class FolderFilesTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testCopyThenMovePreservesContents() throws {
        let source = root.appendingPathComponent("원본.txt")
        try Data("내용".utf8).write(to: source)
        let folder = root.appendingPathComponent("폴더")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FolderFiles.transfer([source], to: folder, move: false)
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: folder.appendingPathComponent("원본.txt")))
        let moved = root.appendingPathComponent("이동.txt")
        try FileManager.default.moveItem(at: source, to: moved)
        try FolderFiles.transfer([moved], to: folder, move: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("이동.txt")), Data("내용".utf8))
    }

    func testCollisionDoesNotOverwriteOrPartiallyStart() throws {
        let destination = root.appendingPathComponent("대상")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("새 파일".utf8).write(to: a)
        try Data("새 파일".utf8).write(to: b)
        try Data("기존 파일".utf8).write(to: destination.appendingPathComponent("b"))
        XCTAssertThrowsError(try FolderFiles.transfer([a, b], to: destination, move: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a").path))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("b")), Data("기존 파일".utf8))
    }

    func testRejectsRecursiveAndInvalidDestinations() throws {
        let child = root.appendingPathComponent("하위")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        XCTAssertThrowsError(try FolderFiles.destination(for: root, in: child))
        XCTAssertThrowsError(try FolderFiles.destination(for: child, in: root))
        let alias = root.appendingPathComponent("링크")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: child)
        XCTAssertThrowsError(try FolderFiles.destination(for: root, in: alias))
        for name in ["", ".", "..", "../외부", "a/b", "a:b"] {
            XCTAssertThrowsError(try FolderFiles.namedURL(name, in: root))
        }
    }

    func testFoldersFirstNaturalOrderAndHiddenFiles() throws {
        for name in ["파일10.txt", "파일2.txt", ".숨김"] { try Data().write(to: root.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("폴더"), withIntermediateDirectories: false)
        XCTAssertEqual(try FolderFiles.list(root, sort: .name).map(\.name), ["폴더", "파일2.txt", "파일10.txt"])
    }

    func testDuplicateSourceNamesAreRejectedBeforeCopying() throws {
        let folders = ["A", "B", "대상"].map { root.appendingPathComponent($0) }
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        let sources = folders.prefix(2).map { $0.appendingPathComponent("같은 이름.txt") }
        for source in sources { try Data("원본".utf8).write(to: source) }
        XCTAssertThrowsError(try FolderFiles.transfer(sources, to: folders[2], move: true))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folders[2].path).isEmpty)
        XCTAssertTrue(sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}

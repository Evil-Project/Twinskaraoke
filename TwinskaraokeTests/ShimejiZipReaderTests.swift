import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Resource pack extraction")
struct ShimejiZipReaderTests {
    @Test("Normal nested pack files extract successfully")
    func nestedFile() throws {
        try withArchive(valid) { archive, root in
            try ShimejiZipReader.extract(zipURL: archive, to: root)
            #expect(try String(contentsOf: root.appendingPathComponent("img/frame.txt"), encoding: .utf8) == "sprite")
        }
    }

    @Test("Parent traversal cannot write outside the pack")
    func parentTraversal() throws {
        try withArchive(traversal) { archive, root in
            #expect(throws: ShimejiZipReader.ZipError.self) {
                try ShimejiZipReader.extract(zipURL: archive, to: root)
            }
            #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
        }
    }

    @Test("Existing symbolic links cannot redirect extraction outside the pack")
    func symlinkEscape() throws {
        try withArchive(symlink) { archive, root in
            let outside = root.deletingLastPathComponent().appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
            #expect(throws: ShimejiZipReader.ZipError.self) {
                try ShimejiZipReader.extract(zipURL: archive, to: root)
            }
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("escaped.txt").path))
        }
    }

    @Test("Replacing an opened directory with a symlink cannot redirect a write")
    func replacedDirectoryCannotRedirectWrite() throws {
        try withArchive(valid) { archive, root in
            let fm = FileManager.default
            let outside = root.deletingLastPathComponent().appendingPathComponent("outside")
            try fm.createDirectory(at: outside, withIntermediateDirectories: true)
            try ShimejiZipReader.extract(zipURL: archive, to: root) { _ in
                let directory = root.appendingPathComponent("img")
                try fm.moveItem(at: directory, to: root.appendingPathComponent("original-img"))
                try fm.createSymbolicLink(at: directory, withDestinationURL: outside)
            }
            #expect(!fm.fileExists(atPath: outside.appendingPathComponent("frame.txt").path))
            #expect(try String(contentsOf: root.appendingPathComponent("original-img/frame.txt"), encoding: .utf8) == "sprite")
        }
    }

    private func withArchive(_ encoded: String, body: (URL, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("pack")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("pack.zip")
        try #require(Data(base64Encoded: encoded)).write(to: archive)
        try body(archive, root)
    }
    private let valid = "UEsDBBQAAAAAAJBoJl2ejx01BgAAAAYAAAANAAAAaW1nL2ZyYW1lLnR4dHNwcml0ZVBLAQIUAxQAAAAAAJBoJl2ejx01BgAAAAYAAAANAAAAAAAAAAAAAACAAQAAAABpbWcvZnJhbWUudHh0UEsFBgAAAAABAAEAOwAAADEAAAAAAA=="
    private let traversal = "UEsDBBQAAAAAAJBoJl2ejx01BgAAAAYAAAAOAAAALi4vZXNjYXBlZC50eHRzcHJpdGVQSwECFAMUAAAAAACQaCZdno8dNQYAAAAGAAAADgAAAAAAAAAAAAAAgAEAAAAALi4vZXNjYXBlZC50eHRQSwUGAAAAAAEAAQA8AAAAMgAAAAAA"
    private let symlink = "UEsDBBQAAAAAAJBoJl2ejx01BgAAAAYAAAASAAAAbGlua2VkL2VzY2FwZWQudHh0c3ByaXRlUEsBAhQDFAAAAAAAkGgmXZ6PHTUGAAAABgAAABIAAAAAAAAAAAAAAIABAAAAAGxpbmtlZC9lc2NhcGVkLnR4dFBLBQYAAAAAAQABAEAAAAA2AAAAAAA="
}

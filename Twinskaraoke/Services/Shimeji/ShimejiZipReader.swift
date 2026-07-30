import Compression
import Foundation

/// A minimal, dependency-free ZIP reader. iOS has no built-in ZIP archive
/// API, and this project doesn't otherwise depend on a third-party archiving
/// library, so this implements just enough of the format to extract the
/// Shimeji resource pack: reading the central directory, then STORE (0) or
/// DEFLATE (8) compressed entries. It does not handle encryption, zip64, or
/// multi-part archives — the resource pack is built with plain `zip`, which
/// doesn't need any of those.
nonisolated enum ShimejiZipReader {
    nonisolated enum ZipError: Error {
        case notAZip
        case corruptArchive
        case unsupportedCompressionMethod(UInt16)
        case decompressionFailed
        case unsafePath
    }

    /// Extracts every file entry in `zipURL` into `destinationDirectory`,
    /// recreating the archive's internal folder structure.
    static func extract(zipURL: URL, to destinationDirectory: URL) throws {
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let entries = try readCentralDirectory(data)

        let fm = FileManager.default
        let canonicalDestination = destinationDirectory.standardized.path

        for entry in entries where !entry.isDirectory {
            // Zip-slip protection: validate path is safe before extraction
            try validatePath(entry.path)

            let destination = destinationDirectory.appendingPathComponent(entry.path)
            let canonicalFile = destination.standardized.path

            // Ensure resolved path remains under destination directory
            guard canonicalFile.hasPrefix(canonicalDestination + "/") || canonicalFile == canonicalDestination else {
                throw ZipError.unsafePath
            }

            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let fileData = try extractFileData(data, entry: entry)
            try fileData.write(to: destination, options: .atomic)
        }
    }

    /// Validates that a path from a zip archive is safe to extract
    private static func validatePath(_ path: String) throws {
        // Reject absolute paths
        guard !path.hasPrefix("/") else {
            throw ZipError.unsafePath
        }

        // Reject paths containing ".." components
        let components = path.split(separator: "/")
        for component in components {
            if component == ".." {
                throw ZipError.unsafePath
            }
        }
    }

    // MARK: - Central directory parsing

    private nonisolated struct Entry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        var isDirectory: Bool { path.hasSuffix("/") }
    }

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        // Locate the End Of Central Directory record by scanning backward for
        // its signature. The comment field (rarely used, but variable length)
        // means we can't assume a fixed offset from the end of the file.
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard let eocdOffset = lastRange(of: eocdSignature, in: data) else {
            throw ZipError.notAZip
        }

        // Standard EOCD record is at least 22 bytes long
        guard eocdOffset + 22 <= data.count else {
            throw ZipError.corruptArchive
        }

        func u16(_ offset: Int) throws -> UInt16 {
            guard offset + 2 <= data.count else { throw ZipError.corruptArchive }
            return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }
        func u32(_ offset: Int) throws -> UInt32 {
            guard offset + 4 <= data.count else { throw ZipError.corruptArchive }
            return UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
        }

        let totalEntries = Int(try u16(eocdOffset + 10))
        let centralDirSize = Int(try u32(eocdOffset + 12))
        let centralDirOffset = Int(try u32(eocdOffset + 16))

        guard centralDirOffset >= 0, centralDirOffset + centralDirSize <= data.count else {
            throw ZipError.corruptArchive
        }

        var entries: [Entry] = []
        entries.reserveCapacity(totalEntries)
        var cursor = centralDirOffset

        for _ in 0 ..< totalEntries {
            // Minimum Central Directory Header size is 46 bytes
            guard cursor + 46 <= data.count else { throw ZipError.corruptArchive }
            guard try u32(cursor) == 0x02014B50 else { throw ZipError.corruptArchive }

            let method = try u16(cursor + 10)
            let compressedSize = Int(try u32(cursor + 20))
            let uncompressedSize = Int(try u32(cursor + 24))
            let nameLength = Int(try u16(cursor + 28))
            let extraLength = Int(try u16(cursor + 30))
            let commentLength = Int(try u16(cursor + 32))
            let localHeaderOffset = Int(try u32(cursor + 42))

            let nameStart = cursor + 46
            let totalEntryLength = 46 + nameLength + extraLength + commentLength
            guard cursor + totalEntryLength <= data.count else {
                throw ZipError.corruptArchive
            }

            guard let name = String(
                data: data.subdata(in: nameStart ..< nameStart + nameLength),
                encoding: .utf8
            ) else {
                throw ZipError.corruptArchive
            }

            entries.append(Entry(
                path: name,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))

            cursor += totalEntryLength
        }

        return entries
    }

    private static func extractFileData(_ data: Data, entry: Entry) throws -> Data {
        func u16(_ offset: Int) throws -> UInt16 {
            guard offset + 2 <= data.count else { throw ZipError.corruptArchive }
            return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }
        func u32(_ offset: Int) throws -> UInt32 {
            guard offset + 4 <= data.count else { throw ZipError.corruptArchive }
            return UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
        }

        let localOffset = entry.localHeaderOffset
        guard localOffset >= 0, localOffset + 30 <= data.count else { throw ZipError.corruptArchive }
        guard try u32(localOffset) == 0x04034B50 else { throw ZipError.corruptArchive }

        let nameLength = Int(try u16(localOffset + 26))
        let extraLength = Int(try u16(localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength
        let dataEnd = dataStart + entry.compressedSize

        guard dataStart <= dataEnd, dataEnd <= data.count else { throw ZipError.corruptArchive }
        let compressed = data.subdata(in: dataStart ..< dataEnd)

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try inflateRaw(compressed, uncompressedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    /// Decompresses a raw DEFLATE stream (RFC 1951 — no zlib/gzip wrapper).
    /// Despite the name, Apple's Compression framework's `COMPRESSION_ZLIB`
    /// algorithm operates on raw deflate data, which is exactly what ZIP's
    /// method-8 entries contain.
    private static func inflateRaw(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var output = Data(count: uncompressedSize)
        let writtenCount: Int = output.withUnsafeMutableBytes { destRaw in
            compressed.withUnsafeBytes { srcRaw in
                compression_decode_buffer(
                    destRaw.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    srcRaw.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard writtenCount == uncompressedSize else {
            throw ZipError.decompressionFailed
        }
        return output
    }

    private static func lastRange(of pattern: [UInt8], in data: Data) -> Int? {
        guard !pattern.isEmpty, data.count >= pattern.count else { return nil }
        let base = data.startIndex
        var i = data.count - pattern.count
        while i >= 0 {
            var matched = true
            for j in 0 ..< pattern.count where data[base + i + j] != pattern[j] {
                matched = false
                break
            }
            if matched { return base + i }
            i -= 1
        }
        return nil
    }
}

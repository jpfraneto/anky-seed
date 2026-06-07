import Foundation
import zlib
#if SWIFT_PACKAGE
import AnkyProtocol
#endif

struct BackupImportResult: Equatable {
    let ankyCount: Int
    let reflectionCount: Int
}

enum BackupImportError: LocalizedError {
    case unsupportedFile
    case invalidBackup
    case encryptedZip
    case unsupportedCompression(Int)
    case corruptZip
    case noImportableData

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "Choose a .zip backup, .anky file, or exported reflection JSON."
        case .invalidBackup:
            return "That backup could not be read."
        case .encryptedZip:
            return "Encrypted zip backups are not supported."
        case .unsupportedCompression:
            return "That zip backup uses unsupported compression."
        case .corruptZip:
            return "That zip backup appears to be corrupt."
        case .noImportableData:
            return "No .anky files or reflections were found in that import."
        }
    }
}

struct BackupImporter {
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let sessionIndexStore: SessionIndexStore
    private let appOpenStore: AppOpenStore

    init(
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        sessionIndexStore: SessionIndexStore = SessionIndexStore(),
        appOpenStore: AppOpenStore = AppOpenStore()
    ) {
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.sessionIndexStore = sessionIndexStore
        self.appOpenStore = appOpenStore
    }

    func importBackup(from url: URL) throws -> BackupImportResult {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let imported: ImportedBackupData
        switch url.pathExtension.lowercased() {
        case "zip":
            imported = try importZip(data)
        case "anky":
            imported = try importAnky(data)
        case "json":
            imported = try importReflectionJSON(data)
        default:
            throw BackupImportError.unsupportedFile
        }

        guard imported.result.ankyCount > 0 || imported.result.reflectionCount > 0 else {
            throw BackupImportError.noImportableData
        }

        if let earliestAnkyDate = imported.earliestAnkyDate {
            appOpenStore.recordEarlierFirstOpenDate(earliestAnkyDate)
        }
        _ = try? sessionIndexStore.rebuild(archive: archive, reflectionStore: reflectionStore)
        return imported.result
    }

    private func importZip(_ data: Data) throws -> ImportedBackupData {
        let entries = try ZipArchiveReader(data: data).entries()
        var entryDataByPath = [String: Data]()
        var entryDateByPath = [String: Date]()

        for entry in entries where isSafeBackupPath(entry.path) {
            entryDataByPath[entry.path] = entry.data
            entryDateByPath[entry.path] = entry.modificationDate
        }

        var importedHashByBackupHash = [String: String]()
        var earliestAnkyDate: Date?
        var ankyCount = 0
        for (path, data) in entryDataByPath where path.hasSuffix(".anky") {
            guard let text = String(data: data, encoding: .utf8) else {
                continue
            }
            let saved = try archive.save(Self.normalizedImportedAnkyText(text))
            let backupHash = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            importedHashByBackupHash[backupHash] = saved.hash
            earliestAnkyDate = minDate(earliestAnkyDate, saved.createdAt)
            ankyCount += 1
        }

        var reflectionCount = 0
        for (path, data) in entryDataByPath where path.hasSuffix(".reflection.md") {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            let hash = String(filename.dropLast(".reflection.md".count))
            let localHash = importedHashByBackupHash[hash] ?? hash
            guard hash.isAnkyHash, archiveContains(hash: localHash) else {
                continue
            }
            guard let reflectionText = String(data: data, encoding: .utf8) else {
                continue
            }

            let prefix = pathPrefix(for: path)
            let titlePath = "\(prefix)\(hash).title.txt"
            let processingPath = "\(prefix)\(hash).processing.json"
            let processing = entryDataByPath[processingPath].flatMap { try? JSONDecoder().decode(BackupProcessingInfo.self, from: $0) }
            let title = entryDataByPath[titlePath]
                .flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let createdAt = processing?.createdAtDate ?? entryDateByPath[path] ?? Date()

            try reflectionStore.save(LocalReflection(
                hash: localHash,
                title: title?.isEmpty == false ? title! : "Imported reflection",
                reflection: reflectionText,
                createdAt: createdAt,
                creditsRemaining: processing?.creditsRemaining
            ))
            reflectionCount += 1
        }

        for (_, data) in entryDataByPath where looksLikeReflectionJSON(data) {
            if try importReflectionJSON(data).result.reflectionCount > 0 {
                reflectionCount += 1
            }
        }

        return ImportedBackupData(
            result: BackupImportResult(ankyCount: ankyCount, reflectionCount: reflectionCount),
            earliestAnkyDate: earliestAnkyDate
        )
    }

    private func importAnky(_ data: Data) throws -> ImportedBackupData {
        guard let text = String(data: data, encoding: .utf8) else {
            throw BackupImportError.invalidBackup
        }
        let saved = try archive.save(Self.normalizedImportedAnkyText(text))
        return ImportedBackupData(
            result: BackupImportResult(ankyCount: 1, reflectionCount: 0),
            earliestAnkyDate: saved.createdAt
        )
    }

    private func importReflectionJSON(_ data: Data) throws -> ImportedBackupData {
        let reflection = try JSONDecoder.reflectionImportDecoder.decode(LocalReflection.self, from: data)
        try reflectionStore.save(reflection)
        return ImportedBackupData(
            result: BackupImportResult(ankyCount: 0, reflectionCount: 1),
            earliestAnkyDate: nil
        )
    }

    private func looksLikeReflectionJSON(_ data: Data) -> Bool {
        (try? JSONDecoder.reflectionImportDecoder.decode(LocalReflection.self, from: data)) != nil
    }

    private func archiveContains(hash: String) -> Bool {
        (try? archive.load(hash: hash)) != nil
    }

    private func isSafeBackupPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("..") && !path.contains("\\")
    }

    private func pathPrefix(for path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else {
            return ""
        }
        return String(path[...slash])
    }

    private func minDate(_ left: Date?, _ right: Date) -> Date {
        guard let left else {
            return right
        }
        return min(left, right)
    }

    private static func normalizedImportedAnkyText(_ text: String) -> String {
        var lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if lines.last == "" {
            lines.removeLast()
        }

        return lines.map { line in
            guard let separator = line.firstIndex(of: " ") else {
                return line
            }

            let timeText = line[..<separator]
            let characterText = line[line.index(after: separator)...]
            guard characterText == "SPACE" else {
                return line
            }
            return "\(timeText)  "
        }
        .joined(separator: "\n")
    }
}

struct BackupExporter {
    private let archive: LocalAnkyArchive
    private let reflectionStore: ReflectionStore
    private let fileManager: FileManager

    init(
        archive: LocalAnkyArchive = LocalAnkyArchive(),
        reflectionStore: ReflectionStore = ReflectionStore(),
        fileManager: FileManager = .default
    ) {
        self.archive = archive
        self.reflectionStore = reflectionStore
        self.fileManager = fileManager
    }

    func exportBackup() throws -> URL? {
        let ankys = archive.list()
        let reflections = reflectionStore.list()
        guard !ankys.isEmpty || !reflections.isEmpty else {
            return nil
        }

        let createdAt = Date()
        var writer = ZipArchiveWriter()
        let manifest = BackupManifest(
            exportVersion: 1,
            createdAt: ISO8601DateFormatter.ankyBackup.string(from: createdAt),
            ankyCount: ankys.count,
            reflectionCount: reflections.count
        )
        let manifestData = try JSONEncoder.backupExportEncoder.encode(manifest)
        writer.add(path: "manifest.json", data: manifestData, modificationDate: createdAt)

        for anky in ankys {
            writer.add(path: "files/\(anky.hash).anky", data: Data(anky.text.utf8), modificationDate: anky.createdAt)
        }

        let reflectionEncoder = JSONEncoder.backupExportEncoder
        for reflection in reflections {
            let data = try reflectionEncoder.encode(reflection)
            writer.add(path: "reflections/\(reflection.hash).json", data: data, modificationDate: reflection.createdAt)
        }

        let backupURL = try backupURL(for: createdAt)
        try writer.data().write(to: backupURL, options: [.atomic])
        return backupURL
    }

    func exportFormattedWritings() throws -> URL? {
        let ankys = archive.list()
        guard !ankys.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let lines = ankys.map { anky in
            "\(formatter.string(from: anky.createdAt)):\(anky.reconstructedText)"
        }

        let exportURL = try formattedExportURL(for: Date())
        try lines.joined(separator: "\n\n").write(to: exportURL, atomically: true, encoding: .utf8)
        return exportURL
    }

    private func backupURL(for date: Date) throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("AnkyBackups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let url = directory.appendingPathComponent("anky-backup-\(formatter.string(from: date)).zip")
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return url
    }

    private func formattedExportURL(for date: Date) throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("AnkyExports", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let url = directory.appendingPathComponent("anky-writings-\(formatter.string(from: date)).md")
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return url
    }

    private static func hashtag(_ tag: String) -> String {
        let cleaned = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)
            .lowercased()
        return cleaned.isEmpty ? "" : "#\(cleaned)"
    }
}

private struct BackupManifest: Encodable {
    let exportVersion: Int
    let createdAt: String
    let ankyCount: Int
    let reflectionCount: Int
}

private struct ImportedBackupData {
    let result: BackupImportResult
    let earliestAnkyDate: Date?
}

private struct BackupProcessingInfo: Decodable {
    let createdAt: String?
    let creditsRemaining: Int?

    var createdAtDate: Date? {
        guard let createdAt else {
            return nil
        }
        return ISO8601DateFormatter.ankyBackup.date(from: createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case creditsRemaining = "credits_remaining"
    }
}

private struct ZipEntry {
    let path: String
    let data: Data
    let modificationDate: Date?
}

private struct ZipArchiveWriter {
    private struct Entry {
        let path: String
        let data: Data
        let modificationDate: Date
    }

    private var entries = [Entry]()

    mutating func add(path: String, data: Data, modificationDate: Date) {
        entries.append(Entry(path: path, data: data, modificationDate: modificationDate))
    }

    func data() -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let localHeaderOffset = UInt32(archive.count)
            let nameData = Data(entry.path.utf8)
            let checksum = entry.data.crc32Checksum
            let dateTime = Self.dosDateTime(from: entry.modificationDate)
            let size = UInt32(entry.data.count)

            archive.appendUInt32(0x0403_4B50)
            archive.appendUInt16(20)
            archive.appendUInt16(0x0800)
            archive.appendUInt16(0)
            archive.appendUInt16(dateTime.time)
            archive.appendUInt16(dateTime.date)
            archive.appendUInt32(checksum)
            archive.appendUInt32(size)
            archive.appendUInt32(size)
            archive.appendUInt16(UInt16(nameData.count))
            archive.appendUInt16(0)
            archive.append(nameData)
            archive.append(entry.data)

            centralDirectory.appendUInt32(0x0201_4B50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(dateTime.time)
            centralDirectory.appendUInt16(dateTime.date)
            centralDirectory.appendUInt32(checksum)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt16(UInt16(nameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(localHeaderOffset)
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        archive.appendUInt32(0x0605_4B50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(centralDirectory.count))
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)

        return archive
    }

    private static func dosDateTime(from date: Date) -> (date: UInt16, time: UInt16) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, components.year ?? 1980) - 1980
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = (components.second ?? 0) / 2
        return (
            UInt16((year << 9) | (month << 5) | day),
            UInt16((hour << 11) | (minute << 5) | second)
        )
    }
}

private struct ZipArchiveReader {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func entries() throws -> [ZipEntry] {
        let end = try endOfCentralDirectory()
        var offset = end.centralDirectoryOffset
        var result = [ZipEntry]()

        for _ in 0..<end.entryCount {
            guard data.uint32(at: offset) == 0x0201_4B50 else {
                throw BackupImportError.corruptZip
            }

            let flags = data.uint16(at: offset + 8)
            let method = Int(data.uint16(at: offset + 10))
            let modifiedTime = data.uint16(at: offset + 12)
            let modifiedDate = data.uint16(at: offset + 14)
            let compressedSize = Int(data.uint32(at: offset + 20))
            let uncompressedSize = Int(data.uint32(at: offset + 24))
            let nameLength = Int(data.uint16(at: offset + 28))
            let extraLength = Int(data.uint16(at: offset + 30))
            let commentLength = Int(data.uint16(at: offset + 32))
            let localHeaderOffset = Int(data.uint32(at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else {
                throw BackupImportError.corruptZip
            }

            guard flags & 0x0001 == 0 else {
                throw BackupImportError.encryptedZip
            }

            let pathData = data.subdata(in: nameStart..<nameEnd)
            guard let path = String(data: pathData, encoding: .utf8), !path.hasSuffix("/") else {
                offset = nameEnd + extraLength + commentLength
                continue
            }

            result.append(ZipEntry(
                path: path,
                data: try fileData(
                    localHeaderOffset: localHeaderOffset,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                ),
                modificationDate: Self.date(dosDate: modifiedDate, dosTime: modifiedTime)
            ))

            offset = nameEnd + extraLength + commentLength
        }

        return result
    }

    private func fileData(
        localHeaderOffset: Int,
        method: Int,
        compressedSize: Int,
        uncompressedSize: Int
    ) throws -> Data {
        guard data.uint32(at: localHeaderOffset) == 0x0403_4B50 else {
            throw BackupImportError.corruptZip
        }

        let nameLength = Int(data.uint16(at: localHeaderOffset + 26))
        let extraLength = Int(data.uint16(at: localHeaderOffset + 28))
        let payloadStart = localHeaderOffset + 30 + nameLength + extraLength
        let payloadEnd = payloadStart + compressedSize
        guard payloadStart >= 0, payloadEnd <= data.count else {
            throw BackupImportError.corruptZip
        }

        let payload = data.subdata(in: payloadStart..<payloadEnd)
        switch method {
        case 0:
            return payload
        case 8:
            return try payload.inflateRawDeflate(uncompressedSize: uncompressedSize)
        default:
            throw BackupImportError.unsupportedCompression(method)
        }
    }

    private func endOfCentralDirectory() throws -> (entryCount: Int, centralDirectoryOffset: Int) {
        let minimumSize = 22
        guard data.count >= minimumSize else {
            throw BackupImportError.corruptZip
        }

        let lowerBound = Swift.max(0, data.count - 65_557)
        var offset = data.count - minimumSize
        while offset >= lowerBound {
            if data.uint32(at: offset) == 0x0605_4B50 {
                return (
                    entryCount: Int(data.uint16(at: offset + 10)),
                    centralDirectoryOffset: Int(data.uint32(at: offset + 16))
                )
            }
            offset -= 1
        }

        throw BackupImportError.corruptZip
    }

    private static func date(dosDate: UInt16, dosTime: UInt16) -> Date? {
        var components = DateComponents()
        components.year = Int((dosDate >> 9) & 0x7F) + 1980
        components.month = Int((dosDate >> 5) & 0x0F)
        components.day = Int(dosDate & 0x1F)
        components.hour = Int((dosTime >> 11) & 0x1F)
        components.minute = Int((dosTime >> 5) & 0x3F)
        components.second = Int(dosTime & 0x1F) * 2
        return Calendar.current.date(from: components)
    }
}

private extension Data {
    var crc32Checksum: UInt32 {
        withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: Bytef.self).baseAddress else {
                return UInt32(zlib.crc32(0, nil, 0))
            }
            return UInt32(zlib.crc32(0, base, uInt(count)))
        }
    }

    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0x0000_00FF))
        append(UInt8((value >> 8) & 0x0000_00FF))
        append(UInt8((value >> 16) & 0x0000_00FF))
        append(UInt8((value >> 24) & 0x0000_00FF))
    }

    func uint16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else {
            return 0
        }
        let byte0 = UInt16(self[offset])
        let byte1 = UInt16(self[offset + 1])
        return byte0 | (byte1 << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else {
            return 0
        }
        let byte0 = UInt32(self[offset])
        let byte1 = UInt32(self[offset + 1])
        let byte2 = UInt32(self[offset + 2])
        let byte3 = UInt32(self[offset + 3])
        return byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
    }

    func inflateRawDeflate(uncompressedSize: Int) throws -> Data {
        var output = Data(count: uncompressedSize)
        var stream = z_stream()
        let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else {
            throw BackupImportError.corruptZip
        }
        defer {
            inflateEnd(&stream)
        }

        let result = withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                guard let inputBase = inputBytes.bindMemory(to: Bytef.self).baseAddress,
                      let outputBase = outputBytes.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_DATA_ERROR
                }

                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBase)
                stream.avail_in = uInt(count)
                stream.next_out = outputBase
                stream.avail_out = uInt(uncompressedSize)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END else {
            throw BackupImportError.corruptZip
        }

        output.count = Int(stream.total_out)
        return output
    }
}

private extension JSONDecoder {
    static var reflectionImportDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var backupExportEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension ISO8601DateFormatter {
    static let ankyBackup: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension String {
    var isAnkyHash: Bool {
        count == 64 && allSatisfy { character in
            character.isNumber || ("a"..."f").contains(character)
        }
    }
}

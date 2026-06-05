import CryptoKit
import Foundation
import Security

struct ICloudBackupStatus: Equatable {
    let isEnabled: Bool
    let lastBackupDate: Date?
}

enum ICloudBackupError: LocalizedError, Equatable {
    case iCloudUnavailable
    case noLocalData
    case missingRemoteBackup
    case invalidEnvelope
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud backup is not available on this device."
        case .noLocalData:
            return "There is no writing to back up yet."
        case .missingRemoteBackup:
            return "No Anky iCloud backup was found."
        case .invalidEnvelope:
            return "The iCloud backup could not be read."
        case .encryptionFailed:
            return "The iCloud backup could not be encrypted."
        case .decryptionFailed:
            return "The iCloud backup could not be decrypted."
        }
    }
}

struct ICloudBackupStore {
    private static let enabledKey = "anky.iCloudPrivateBackupEnabled"
    private static let lastBackupDateKey = "anky.iCloudPrivateBackupLastDate"
    private static let backupFileName = "anky-private-backup.v1"
    private static let backupDirectoryName = "Anky"
    private static let encryptionInfo = Data("anky.private.icloud.backup.v1".utf8)

    private let identityStore: WriterIdentityStore
    private let backupExporter: BackupExporter
    private let backupImporter: BackupImporter
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let ubiquityContainerURL: URL?

    init(
        identityStore: WriterIdentityStore = WriterIdentityStore(),
        backupExporter: BackupExporter = BackupExporter(),
        backupImporter: BackupImporter = BackupImporter(),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        ubiquityContainerURL: URL? = nil
    ) {
        self.identityStore = identityStore
        self.backupExporter = backupExporter
        self.backupImporter = backupImporter
        self.defaults = defaults
        self.fileManager = fileManager
        self.ubiquityContainerURL = ubiquityContainerURL
    }

    var status: ICloudBackupStatus {
        ICloudBackupStatus(
            isEnabled: defaults.bool(forKey: Self.enabledKey),
            lastBackupDate: defaults.object(forKey: Self.lastBackupDateKey) as? Date
        )
    }

    func setEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.enabledKey)
    }

    func hasRestorableBackup() -> Bool {
        guard identityStore.hasICloudRecoveryPhraseBackup(),
              let backupURL = try? remoteBackupURL() else {
            return false
        }
        return fileManager.fileExists(atPath: backupURL.path)
    }

    func enableAndBackUpNow() throws {
        try identityStore.backUpRecoveryPhraseToICloudKeychain()
        setEnabled(true)
        try backUpNow()
    }

    func backUpIfEnabled() {
        guard status.isEnabled else {
            return
        }
        try? backUpNow()
    }

    func backUpNow() throws {
        let phrase = try identityStore.loadOrCreateRecoveryPhrase()
        guard let backupZipURL = try backupExporter.exportBackup() else {
            throw ICloudBackupError.noLocalData
        }
        let zipData = try Data(contentsOf: backupZipURL)
        let envelope = try Self.encrypt(zipData, recoveryPhrase: phrase)
        let envelopeData = try JSONEncoder.iCloudBackupEncoder.encode(envelope)
        let backupURL = try remoteBackupURL()
        try fileManager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try envelopeData.write(to: backupURL, options: [.atomic])
        defaults.set(Date(), forKey: Self.lastBackupDateKey)
    }

    @discardableResult
    func restoreFromICloud() throws -> BackupImportResult {
        _ = try identityStore.recoverFromICloudKeychainBackup()
        let phrase = try identityStore.loadOrCreateRecoveryPhrase()
        let backupURL = try remoteBackupURL()
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw ICloudBackupError.missingRemoteBackup
        }
        let envelopeData = try Data(contentsOf: backupURL)
        let envelope = try JSONDecoder.iCloudBackupDecoder.decode(ICloudBackupEnvelope.self, from: envelopeData)
        let zipData = try Self.decrypt(envelope, recoveryPhrase: phrase)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("anky-icloud-restore-\(UUID().uuidString)")
            .appendingPathExtension("zip")
        try zipData.write(to: temporaryURL, options: [.atomic])
        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }
        let result = try backupImporter.importBackup(from: temporaryURL)
        setEnabled(true)
        defaults.set(Date(), forKey: Self.lastBackupDateKey)
        return result
    }

    static func encrypt(_ data: Data, recoveryPhrase: RecoveryPhrase) throws -> ICloudBackupEnvelope {
        let salt = try randomData(count: 16)
        let key = key(for: recoveryPhrase, salt: salt)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw ICloudBackupError.encryptionFailed
        }
        return ICloudBackupEnvelope(
            version: 1,
            algorithm: "AES-GCM-HKDF-SHA256",
            createdAt: Date(),
            salt: salt,
            payload: combined
        )
    }

    static func decrypt(_ envelope: ICloudBackupEnvelope, recoveryPhrase: RecoveryPhrase) throws -> Data {
        guard envelope.version == 1,
              envelope.algorithm == "AES-GCM-HKDF-SHA256" else {
            throw ICloudBackupError.invalidEnvelope
        }
        do {
            let key = key(for: recoveryPhrase, salt: envelope.salt)
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.payload)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw ICloudBackupError.decryptionFailed
        }
    }

    private func remoteBackupURL() throws -> URL {
        let container = ubiquityContainerURL ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        guard let container else {
            throw ICloudBackupError.iCloudUnavailable
        }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(Self.backupDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.backupFileName)
    }

    private static func key(for recoveryPhrase: RecoveryPhrase, salt: Data) -> SymmetricKey {
        let input = SymmetricKey(data: Data(recoveryPhrase.text.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            salt: salt,
            info: encryptionInfo,
            outputByteCount: 32
        )
    }

    private static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw ICloudBackupError.encryptionFailed
        }
        return data
    }
}

struct ICloudBackupEnvelope: Codable, Equatable {
    let version: Int
    let algorithm: String
    let createdAt: Date
    let salt: Data
    let payload: Data
}

private extension JSONEncoder {
    static var iCloudBackupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var iCloudBackupDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

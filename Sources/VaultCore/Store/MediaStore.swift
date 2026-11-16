import Foundation
import CryptoKit

/// One stored file. Lives only in the encrypted index; the blob on disk has an opaque name.
public struct MediaEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Uniform type identifier, e.g. "public.jpeg". Empty when unknown.
    public var type: String
    public var size: Int64
    public var addedAt: Date
    /// Small JPEG preview for images, generated when the file is added. Nil for other kinds.
    public var thumbnail: Data?

    public init(id: UUID = UUID(), name: String, type: String, size: Int64, addedAt: Date = Date(), thumbnail: Data? = nil) {
        self.id = id; self.name = name; self.type = type; self.size = size; self.addedAt = addedAt; self.thumbnail = thumbnail
    }

    public var fileExtension: String { (name as NSString).pathExtension.lowercased() }
}

/// Encrypted file store next to the vault file. Media never goes into the `.vault` export;
/// it stays on the device it was added to.
///
/// Layout:   media/index.enc        AES-GCM(JSON [MediaEntry])
///           media/<uuid>.bin       AES-GCM(file bytes)
///
/// Everything is sealed under a key derived from the vault key, so nothing here is readable
/// without unlocking the vault. The index is bound to the vault id; a blob is bound to its entry id.
public struct MediaStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory { self.directory = directory } else {
            self.directory = LocalStore().directory.appendingPathComponent("media", isDirectory: true)
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.enc") }
    private func blobURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).bin") }

    /// Separate key for media so the vault key itself never touches file blobs.
    public static func mediaKey(vaultKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: vaultKey, info: Data("vault.media.v1".utf8), outputByteCount: 32)
    }

    private static func indexAAD(_ vaultID: UUID) -> Data { Data("media-index:".utf8) + withUnsafeBytes(of: vaultID.uuid) { Data($0) } }
    private static func blobAAD(_ id: UUID) -> Data { Data("media-blob:".utf8) + withUnsafeBytes(of: id.uuid) { Data($0) } }

    // MARK: Index

    public func loadIndex(key: SymmetricKey, vaultID: UUID) throws -> [MediaEntry] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let plain = try VaultCipher.open(try Data(contentsOf: indexURL), key: key, aad: Self.indexAAD(vaultID))
        guard let list = try? VaultJSON.decoder().decode([MediaEntry].self, from: plain) else { throw VaultError.corruptFile }
        return list
    }

    public func saveIndex(_ entries: [MediaEntry], key: SymmetricKey, vaultID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plain = try VaultJSON.encoder().encode(entries)
        let sealed = try VaultCipher.seal(plain, key: key, aad: Self.indexAAD(vaultID))
        try sealed.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: Blobs

    /// Encrypts `data` to a new blob. The caller appends the returned entry to the index and saves it.
    public func add(data: Data, name: String, type: String, thumbnail: Data?, key: SymmetricKey) throws -> MediaEntry {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = MediaEntry(name: name, type: type, size: Int64(data.count), thumbnail: thumbnail)
        let sealed = try VaultCipher.seal(data, key: key, aad: Self.blobAAD(entry.id))
        try sealed.write(to: blobURL(entry.id), options: [.atomic, .completeFileProtection])
        return entry
    }

    public func read(_ entry: MediaEntry, key: SymmetricKey) throws -> Data {
        let sealed = try Data(contentsOf: blobURL(entry.id))
        do { return try VaultCipher.open(sealed, key: key, aad: Self.blobAAD(entry.id)) }
        catch { throw VaultError.corruptFile }
    }

    public func remove(_ entry: MediaEntry) {
        try? FileManager.default.removeItem(at: blobURL(entry.id))
    }

    public func wipe() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Bytes on disk for all blobs, for the footer.
    public func diskUsage() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

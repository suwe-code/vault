import Foundation
import CryptoKit

/// On-disk and export format. The header is plaintext JSON (no secrets, nothing
/// that identifies the owner); the body is AES-GCM under a random vault key that
/// is itself wrapped by the master key derived from password + secret key.
public struct VaultHeader: Codable, Equatable, Sendable {
    public var format: String
    public var version: Int
    public var vaultID: UUID
    public var kdf: KDFParams
    public var wrappedVaultKey: Data
    public var createdAt: Date
    public var modifiedAt: Date

    public static let formatName = "vault"
    public static let currentVersion = 1
}

public struct VaultFile: Codable, Equatable, Sendable {
    public var header: VaultHeader
    public var body: Data

    public static let fileExtension = "vault"
    public static let magic = Data("VAULT1\n".utf8)

    public func serialized() throws -> Data {
        return VaultFile.magic + (try VaultJSON.encoder().encode(self))
    }

    public static func parse(_ data: Data) throws -> VaultFile {
        guard data.starts(with: magic) else { throw VaultError.unsupportedFormat }
        do {
            let file = try VaultJSON.decoder().decode(VaultFile.self, from: data.dropFirst(magic.count))
            guard file.header.format == VaultHeader.formatName,
                  file.header.version <= VaultHeader.currentVersion else { throw VaultError.unsupportedFormat }
            return file
        } catch let e as VaultError { throw e } catch { throw VaultError.corruptFile }
    }
}

/// An unlocked vault held in memory. Never persisted as-is.
public struct OpenVault: Sendable {
    public var header: VaultHeader
    public var payload: VaultPayload
    public let vaultKey: SymmetricKey

    private static func aad(_ header: VaultHeader) -> Data {
        withUnsafeBytes(of: header.vaultID.uuid) { Data($0) } + Data("v\(header.version)".utf8)
    }

    // MARK: Create

    public static func create(password: String, secretKey: SecretKey, deviceName: String,
                              iterations: Int = KDFParams.defaultIterations, now: Date = Date()) throws -> OpenVault {
        let kdf = KDFParams.fresh(iterations: iterations)
        let master = try KeyDerivation.masterKey(password: password, secretKey: secretKey, params: kdf)
        let vaultKey = VaultCipher.randomKey()
        let id = UUID()
        var header = VaultHeader(format: VaultHeader.formatName, version: VaultHeader.currentVersion,
                                 vaultID: id, kdf: kdf, wrappedVaultKey: Data(), createdAt: now.vaultRounded, modifiedAt: now.vaultRounded)
        header.wrappedVaultKey = try VaultCipher.seal(VaultCipher.keyData(vaultKey), key: master, aad: aad(header))
        return OpenVault(header: header, payload: VaultPayload(deviceName: deviceName, savedAt: now), vaultKey: vaultKey)
    }

    // MARK: Unlock

    public static func unlock(file: VaultFile, password: String, secretKey: SecretKey) throws -> OpenVault {
        let master = try KeyDerivation.masterKey(password: password, secretKey: secretKey, params: file.header.kdf)
        let keyData = try VaultCipher.open(file.header.wrappedVaultKey, key: master, aad: aad(file.header))
        return try unlock(file: file, vaultKey: SymmetricKey(data: keyData))
    }

    /// Unlock with an already-unwrapped vault key (e.g. released by the device keychain).
    public static func unlock(file: VaultFile, vaultKey: SymmetricKey) throws -> OpenVault {
        let plain = try VaultCipher.open(file.body, key: vaultKey, aad: aad(file.header))
        guard let payload = try? VaultJSON.decoder().decode(VaultPayload.self, from: plain) else { throw VaultError.corruptFile }
        return OpenVault(header: file.header, payload: payload, vaultKey: vaultKey)
    }

    // MARK: Save

    public func sealed(deviceName: String, now: Date = Date()) throws -> VaultFile {
        var p = payload
        p.deviceName = deviceName
        p.savedAt = now.vaultRounded
        p.pruneTombstones(now: now)
        let plain = try VaultJSON.encoder().encode(p)
        var h = header
        h.modifiedAt = now.vaultRounded
        let body = try VaultCipher.seal(plain, key: vaultKey, aad: Self.aad(h))
        return VaultFile(header: h, body: body)
    }

    // MARK: Password change (re-wraps the vault key only; body untouched)

    public func rewrapped(password: String, secretKey: SecretKey, iterations: Int = KDFParams.defaultIterations) throws -> OpenVault {
        var h = header
        h.kdf = KDFParams.fresh(iterations: iterations)
        let master = try KeyDerivation.masterKey(password: password, secretKey: secretKey, params: h.kdf)
        h.wrappedVaultKey = try VaultCipher.seal(VaultCipher.keyData(vaultKey), key: master, aad: Self.aad(h))
        return OpenVault(header: h, payload: payload, vaultKey: vaultKey)
    }

    // MARK: Merge another file (manual sync)

    public mutating func merge(file other: VaultFile, password: String, secretKey: SecretKey) throws -> MergeSummary {
        let opened = try OpenVault.unlock(file: other, password: password, secretKey: secretKey)
        return merge(payload: opened.payload)
    }

    public mutating func merge(payload other: VaultPayload) -> MergeSummary {
        let r = VaultMerge.merge(local: payload.items, incoming: other.items)
        payload.items = r.items
        return r.summary
    }
}

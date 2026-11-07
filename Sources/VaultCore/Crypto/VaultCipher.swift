import Foundation
import CryptoKit

/// AES-256-GCM with a fresh 96-bit nonce per seal. Output is nonce || ciphertext || tag.
public enum VaultCipher {
    public static func seal(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        guard let combined = box.combined else { throw VaultError.cryptoFailed }
        return combined
    }

    public static func open(_ combined: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw VaultError.wrongCredentials
        }
    }

    public static func randomKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    public static func keyData(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }
}

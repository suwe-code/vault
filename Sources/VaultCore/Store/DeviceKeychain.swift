import Foundation
import Security
import LocalAuthentication

/// Per-device secrets that never enter the vault file:
/// - the Secret Key, stored behind the current biometric set (Face ID / Touch ID);
/// - the TOTP seed and the last accepted counter (replay protection).
/// Everything is "this device only": it is excluded from backups and never synced.
public enum DeviceKeychain {
    public static let service = "com.suwe.vault"

    public enum Biometry { case none, touchID, faceID, opticID }

    public static func availableBiometry() -> Biometry {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return .none }
        switch ctx.biometryType {
        case .touchID: return .touchID
        case .faceID: return .faceID
        case .opticID: return .opticID
        default: return .none
        }
    }

    // MARK: Secret key (biometric-gated)

    public static func storeSecretKey(_ key: SecretKey, vaultID: UUID) throws {
        var cfErr: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &cfErr) else {
            throw VaultError.biometricsUnavailable
        }
        let account = "secretkey.\(vaultID.uuidString)"
        delete(account: account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: key.bytes,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    /// Prompts Face ID / Touch ID. Throws `.notEnrolled` if this device has no copy.
    public static func loadSecretKey(vaultID: UUID, reason: String) throws -> SecretKey {
        let ctx = LAContext()
        ctx.localizedReason = reason
        ctx.localizedFallbackTitle = ""   // no passcode fallback; the printed key card is the fallback
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "secretkey.\(vaultID.uuidString)",
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: ctx,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { throw VaultError.keychain(status) }
            return try SecretKey(bytes: data)
        case errSecItemNotFound: throw VaultError.notEnrolled
        case errSecUserCanceled, errSecAuthFailed: throw VaultError.biometricsCancelled
        default: throw VaultError.keychain(status)
        }
    }

    public static func hasSecretKey(vaultID: UUID) -> Bool {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "secretkey.\(vaultID.uuidString)",
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: ctx,
            kSecReturnAttributes as String: true,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: TOTP seed (device-bound, no biometric prompt)

    public static func storeTOTP(_ totp: TOTP, vaultID: UUID) throws {
        try storePlain(totp.secret, account: "totp.\(vaultID.uuidString)")
    }

    public static func loadTOTP(vaultID: UUID) throws -> TOTP? {
        guard let d = try loadPlain(account: "totp.\(vaultID.uuidString)") else { return nil }
        return TOTP(secret: d)
    }

    public static func lastAcceptedCounter(vaultID: UUID) -> UInt64 {
        guard let d = try? loadPlain(account: "totp.counter.\(vaultID.uuidString)"), d.count == 8 else { return 0 }
        return d.withUnsafeBytes { $0.load(as: UInt64.self) }
    }

    public static func setLastAcceptedCounter(_ c: UInt64, vaultID: UUID) {
        var v = c
        try? storePlain(Data(bytes: &v, count: 8), account: "totp.counter.\(vaultID.uuidString)")
    }

    // MARK: Wipe

    public static func wipe(vaultID: UUID) {
        for a in ["secretkey", "totp", "totp.counter"] { delete(account: "\(a).\(vaultID.uuidString)") }
    }

    // MARK: Private

    private static func storePlain(_ data: Data, account: String) throws {
        delete(account: account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    private static func loadPlain(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let d = out as? Data else { throw VaultError.keychain(status) }
        return d
    }

    private static func delete(account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

import Foundation
import Security

/// The second factor that travels with the user, never with the vault file.
/// 160 random bits, shown once as a printed key card and kept in each enrolled
/// device's keychain behind biometrics. Combined with the password in the KDF,
/// so a stolen vault file cannot be brute-forced without it.
public struct SecretKey: Equatable, Hashable, Sendable {
    public static let byteCount = 20
    public static let prefix = "VK1"

    public let bytes: Data

    public init(bytes: Data) throws {
        guard bytes.count == Self.byteCount else { throw VaultError.invalidSecretKey }
        self.bytes = bytes
    }

    public static func generate() -> SecretKey {
        var b = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return try! SecretKey(bytes: Data(b))
    }

    /// VK1-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (32 base32 chars in groups of 4)
    public var formatted: String {
        let raw = Base32.encode(bytes)
        var groups: [String] = []
        var i = raw.startIndex
        while i < raw.endIndex {
            let j = raw.index(i, offsetBy: 4, limitedBy: raw.endIndex) ?? raw.endIndex
            groups.append(String(raw[i..<j]))
            i = j
        }
        return ([Self.prefix] + groups).joined(separator: "-")
    }

    /// Accepts the formatted form, with or without prefix, dashes, spaces, any case.
    public init(parsing text: String) throws {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix(Self.prefix + "-") { s.removeFirst(Self.prefix.count + 1) }
        else if s.hasPrefix(Self.prefix) { s.removeFirst(Self.prefix.count) }
        // 0, 1 and 8 are not in the base32 alphabet; treat them as the letters they resemble.
        s = s.replacingOccurrences(of: "0", with: "O")
             .replacingOccurrences(of: "1", with: "I")
             .replacingOccurrences(of: "8", with: "B")
        guard let data = Base32.decode(s), data.count == Self.byteCount else { throw VaultError.invalidSecretKey }
        self.bytes = data
    }
}

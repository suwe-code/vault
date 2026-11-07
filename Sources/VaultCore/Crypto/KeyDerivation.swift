import Foundation
import CryptoKit
import CommonCrypto

public struct KDFParams: Codable, Equatable, Sendable {
    public var algorithm: String
    public var iterations: Int
    public var salt: Data

    public static let defaultIterations = 1_000_000

    public init(algorithm: String = "PBKDF2-HMAC-SHA256", iterations: Int = KDFParams.defaultIterations, salt: Data) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.salt = salt
    }

    public static func fresh(iterations: Int = KDFParams.defaultIterations) -> KDFParams {
        var b = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return KDFParams(iterations: iterations, salt: Data(b))
    }
}

public enum KeyDerivation {
    /// Unicode-normalise and trim so the same visible password always derives the same key.
    public static func normalize(password: String) -> String {
        password.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping
    }

    public static func pbkdf2(password: String, salt: Data, iterations: Int, length: Int = 32) throws -> Data {
        let pw = Array(normalize(password: password).utf8)
        var out = [UInt8](repeating: 0, count: length)
        let status = salt.withUnsafeBytes { saltPtr -> Int32 in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pw.map { CChar(bitPattern: $0) }, pw.count,
                saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &out, out.count)
        }
        guard status == kCCSuccess else { throw VaultError.kdfFailed }
        return Data(out)
    }

    /// Master key = HKDF( PBKDF2(password) XOR HKDF(secretKey) ).
    /// Two independent secrets; losing either makes the vault file undecryptable.
    public static func masterKey(password: String, secretKey: SecretKey, params: KDFParams) throws -> SymmetricKey {
        guard params.algorithm == "PBKDF2-HMAC-SHA256" else { throw VaultError.unsupportedFormat }
        let pwKey = try pbkdf2(password: password, salt: params.salt, iterations: params.iterations)
        let skKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secretKey.bytes),
            salt: params.salt,
            info: Data("vault.secretkey.v1".utf8),
            outputByteCount: 32)
        let skBytes = skKey.withUnsafeBytes { Data($0) }
        var mixed = Data(count: 32)
        for i in 0..<32 { mixed[i] = pwKey[i] ^ skBytes[i] }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: mixed),
            salt: params.salt,
            info: Data("vault.master.v1".utf8),
            outputByteCount: 32)
    }
}

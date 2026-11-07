import Foundation

public enum VaultError: Error, LocalizedError, Equatable {
    case invalidSecretKey
    case kdfFailed
    case cryptoFailed
    case wrongCredentials
    case unsupportedFormat
    case corruptFile
    case keychain(OSStatus)
    case biometricsUnavailable
    case biometricsCancelled
    case notEnrolled

    public var errorDescription: String? {
        switch self {
        case .invalidSecretKey: return "Secret key is not valid"
        case .kdfFailed: return "Key derivation failed"
        case .cryptoFailed: return "Encryption failed"
        case .wrongCredentials: return "Incorrect password or secret key"
        case .unsupportedFormat: return "Unsupported vault format"
        case .corruptFile: return "Vault file is damaged"
        case .keychain(let s): return "Keychain error \(s)"
        case .biometricsUnavailable: return "Biometrics unavailable"
        case .biometricsCancelled: return "Cancelled"
        case .notEnrolled: return "This device is not enrolled"
        }
    }
}

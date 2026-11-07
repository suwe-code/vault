import Foundation

extension Date {
    /// All vault timestamps are millisecond precision so that a value survives
    /// JSON encoding unchanged and merge comparisons are exact across devices.
    public var vaultRounded: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
    public static func vaultNow() -> Date { Date().vaultRounded }
}

enum VaultJSON {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}

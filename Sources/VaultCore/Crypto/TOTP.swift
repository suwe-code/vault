import Foundation
import CryptoKit

/// RFC 6238 time-based one-time password, compatible with Google Authenticator and Apple Passwords.
public struct TOTP: Equatable, Sendable {
    public let secret: Data
    public let digits: Int
    public let period: TimeInterval

    public init(secret: Data, digits: Int = 6, period: TimeInterval = 30) {
        self.secret = secret
        self.digits = digits
        self.period = period
    }

    public static func generateSecret() -> TOTP {
        var b = [UInt8](repeating: 0, count: 20)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return TOTP(secret: Data(b))
    }

    public func counter(at date: Date) -> UInt64 {
        UInt64(floor(date.timeIntervalSince1970 / period))
    }

    public func code(counter: UInt64) -> String {
        var c = counter.bigEndian
        let msg = Data(bytes: &c, count: 8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: msg, using: SymmetricKey(data: secret))
        let hash = Data(mac)
        let offset = Int(hash[hash.count - 1] & 0x0F)
        let truncated = (UInt32(hash[offset] & 0x7F) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        let mod = UInt32(pow(10, Double(digits)))
        let value = truncated % mod
        return String(format: "%0\(digits)d", value)
    }

    public func code(at date: Date = Date()) -> String { code(counter: counter(at: date)) }

    /// Seconds until the current code rolls over.
    public func secondsRemaining(at date: Date = Date()) -> Int {
        Int(period - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period))
    }

    /// Returns the matched counter if the code is valid within +/- `window` steps, else nil.
    /// Callers must reject a counter they have already accepted (replay protection).
    public func validate(_ input: String, at date: Date = Date(), window: Int = 1) -> UInt64? {
        let cleaned = input.filter(\.isNumber)
        guard cleaned.count == digits else { return nil }
        let now = counter(at: date)
        for delta in -window...window {
            let c = UInt64(Int64(now) + Int64(delta))
            if constantTimeEquals(code(counter: c), cleaned) { return c }
        }
        return nil
    }

    public func provisioningURL(issuer: String, account: String) -> URL {
        var comps = URLComponents()
        comps.scheme = "otpauth"
        comps.host = "totp"
        comps.path = "/\(issuer):\(account)"
        comps.queryItems = [
            URLQueryItem(name: "secret", value: Base32.encode(secret)),
            URLQueryItem(name: "issuer", value: issuer),
            URLQueryItem(name: "algorithm", value: "SHA1"),
            URLQueryItem(name: "digits", value: String(digits)),
            URLQueryItem(name: "period", value: String(Int(period))),
        ]
        return comps.url!
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}

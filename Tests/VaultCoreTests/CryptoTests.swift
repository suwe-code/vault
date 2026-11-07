import Testing
import Foundation
@testable import VaultCore

@Suite struct CryptoTests {
    @Test func base32KnownVector() {
        #expect(Base32.encode(Data("foobar".utf8)) == "MZXW6YTBOI")
        #expect(Base32.decode("MZXW6YTBOI") == Data("foobar".utf8))
        #expect(Base32.decode("mzxw6ytboi======") == Data("foobar".utf8))
        #expect(Base32.decode("MZXW6YTB0!") == nil)
    }

    @Test func secretKeyRoundTrip() throws {
        let k = SecretKey.generate()
        let f = k.formatted
        #expect(f.hasPrefix("VK1-"))
        #expect(f.count == 3 + 8 * 5)
        #expect(try SecretKey(parsing: f) == k)
        #expect(try SecretKey(parsing: f.lowercased().replacingOccurrences(of: "-", with: " ")) == k)
        #expect(throws: VaultError.invalidSecretKey) { try SecretKey(parsing: "VK1-AAAA") }
    }

    @Test func secretKeyToleratesLookalikeDigits() throws {
        let k = SecretKey.generate()
        let typed = k.formatted.replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "I", with: "1")
        #expect(try SecretKey(parsing: typed) == k)
    }

    @Test func pbkdf2RFC7914Vector() throws {
        let out = try KeyDerivation.pbkdf2(password: "passwd", salt: Data("salt".utf8), iterations: 1, length: 64)
        let hex = out.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
    }

    @Test func masterKeyNeedsBothSecrets() throws {
        let params = KDFParams(iterations: 1000, salt: Data(repeating: 7, count: 32))
        let sk1 = SecretKey.generate(), sk2 = SecretKey.generate()
        let a = try KeyDerivation.masterKey(password: "pw", secretKey: sk1, params: params)
        let b = try KeyDerivation.masterKey(password: "pw", secretKey: sk2, params: params)
        let c = try KeyDerivation.masterKey(password: "pw2", secretKey: sk1, params: params)
        let a2 = try KeyDerivation.masterKey(password: " pw\n", secretKey: sk1, params: params)
        #expect(a != b)
        #expect(a != c)
        #expect(a == a2, "whitespace is trimmed")
    }

    @Test func cipherRoundTripAndTamper() throws {
        let key = VaultCipher.randomKey()
        let aad = Data("aad".utf8)
        let ct = try VaultCipher.seal(Data("hello".utf8), key: key, aad: aad)
        #expect(try VaultCipher.open(ct, key: key, aad: aad) == Data("hello".utf8))
        #expect(throws: VaultError.wrongCredentials) { try VaultCipher.open(ct, key: key, aad: Data("x".utf8)) }
        var bad = ct; bad[bad.count - 1] ^= 1
        #expect(throws: VaultError.wrongCredentials) { try VaultCipher.open(bad, key: key, aad: aad) }
    }

    @Test func totpRFC6238Vectors() {
        let totp = TOTP(secret: Data("12345678901234567890".utf8), digits: 8)
        #expect(totp.code(at: Date(timeIntervalSince1970: 59)) == "94287082")
        #expect(totp.code(at: Date(timeIntervalSince1970: 1111111109)) == "07081804")
        #expect(totp.code(at: Date(timeIntervalSince1970: 1234567890)) == "89005924")
        let six = TOTP(secret: Data("12345678901234567890".utf8))
        #expect(six.code(at: Date(timeIntervalSince1970: 59)) == "287082")
    }

    @Test func totpValidateWindowAndFormat() {
        let t = TOTP.generateSecret()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let c = t.counter(at: now)
        #expect(t.validate(t.code(counter: c), at: now) == c)
        #expect(t.validate(t.code(counter: c - 1), at: now) == c - 1)
        #expect(t.validate(t.code(counter: c + 1), at: now) == c + 1)
        #expect(t.validate(t.code(counter: c + 2), at: now) == nil)
        #expect(t.validate("12345", at: now) == nil)
        let url = t.provisioningURL(issuer: "VAULT", account: "MacBook")
        #expect(url.absoluteString.hasPrefix("otpauth://totp/VAULT:MacBook?secret="))
    }
}

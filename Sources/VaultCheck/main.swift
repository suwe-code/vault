// Command-line self-check of VaultCore. Mirrors Tests/VaultCoreTests for environments
// without XCTest / Swift Testing (plain command line tools). Run: swift run VaultCheck
import Foundation
import VaultCore

var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ name: String) {
    if cond() { print("  ok   \(name)") } else { failures += 1; print("  FAIL \(name)") }
}
func throwsError(_ name: String, _ body: () throws -> Void) {
    do { try body(); failures += 1; print("  FAIL \(name) (no error thrown)") } catch { print("  ok   \(name)") }
}

print("Base32")
check(Base32.encode(Data("foobar".utf8)) == "MZXW6YTBOI", "encode vector")
check(Base32.decode("mzxw6ytboi======") == Data("foobar".utf8), "decode tolerant")
check(Base32.decode("MZXW6YTB0!") == nil, "rejects bad chars")

print("SecretKey")
let k = SecretKey.generate()
check(k.formatted.hasPrefix("VK1-") && k.formatted.count == 43, "format \(k.formatted)")
check((try? SecretKey(parsing: k.formatted.lowercased().replacingOccurrences(of: "-", with: " "))) == k, "parse tolerant")
check((try? SecretKey(parsing: k.formatted.replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "I", with: "1"))) == k, "parse lookalike digits")
throwsError("rejects short key") { _ = try SecretKey(parsing: "VK1-AAAA") }

print("PBKDF2")
let out = try! KeyDerivation.pbkdf2(password: "passwd", salt: Data("salt".utf8), iterations: 1, length: 64)
check(out.map { String(format: "%02x", $0) }.joined() == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783", "RFC 7914 vector")
let params = KDFParams(iterations: 1000, salt: Data(repeating: 7, count: 32))
let sk1 = SecretKey.generate(), sk2 = SecretKey.generate()
let a = try! KeyDerivation.masterKey(password: "pw", secretKey: sk1, params: params)
check(a != (try! KeyDerivation.masterKey(password: "pw", secretKey: sk2, params: params)), "secret key changes master key")
check(a != (try! KeyDerivation.masterKey(password: "pw2", secretKey: sk1, params: params)), "password changes master key")
check(a == (try! KeyDerivation.masterKey(password: " pw\n", secretKey: sk1, params: params)), "whitespace trimmed")
let t0 = Date(); _ = try! KeyDerivation.masterKey(password: "pw", secretKey: sk1, params: KDFParams.fresh())
print(String(format: "  info full-cost derivation: %.2f s (%d iterations)", Date().timeIntervalSince(t0), KDFParams.defaultIterations))

print("AES-GCM")
let key = VaultCipher.randomKey(), aad = Data("aad".utf8)
let ct = try! VaultCipher.seal(Data("hello".utf8), key: key, aad: aad)
check((try? VaultCipher.open(ct, key: key, aad: aad)) == Data("hello".utf8), "roundtrip")
throwsError("wrong aad") { _ = try VaultCipher.open(ct, key: key, aad: Data("x".utf8)) }
var bad = ct; bad[bad.count - 1] ^= 1
throwsError("tampered tag") { _ = try VaultCipher.open(bad, key: key, aad: aad) }

print("TOTP")
let t8 = TOTP(secret: Data("12345678901234567890".utf8), digits: 8)
check(t8.code(at: Date(timeIntervalSince1970: 59)) == "94287082", "RFC 6238 T=59")
check(t8.code(at: Date(timeIntervalSince1970: 1111111109)) == "07081804", "RFC 6238 T=1111111109")
check(t8.code(at: Date(timeIntervalSince1970: 1234567890)) == "89005924", "RFC 6238 T=1234567890")
let t6 = TOTP.generateSecret(); let now = Date(timeIntervalSince1970: 1_700_000_000); let c = t6.counter(at: now)
check(t6.validate(t6.code(counter: c), at: now) == c, "validate current")
check(t6.validate(t6.code(counter: c - 1), at: now) == c - 1, "validate previous step")
check(t6.validate(t6.code(counter: c + 2), at: now) == nil, "reject outside window")
check(t6.validate("12345", at: now) == nil, "reject short")
check(t6.provisioningURL(issuer: "VAULT", account: "Mac").absoluteString.hasPrefix("otpauth://totp/VAULT:Mac?secret="), "otpauth url")

print("Vault file")
let sk = SecretKey.generate()
var v = try! OpenVault.create(password: "correct horse", secretKey: sk, deviceName: "Mac", iterations: 1000)
var item = VaultItem(title: "HDFC Savings", category: .bank, fields: Templates.fields(for: .bank))
item.fields[2].value = "50100123456789"
v.payload.items.append(item)
v.payload.items.append(VaultItem(title: "Gmail", category: .login, fields: Templates.fields(for: .login)))
let file = try! v.sealed(deviceName: "Mac")
let bytes = try! file.serialized()
let text = String(decoding: bytes, as: UTF8.self)
check(bytes.starts(with: VaultFile.magic), "magic header")
check(!text.contains("50100123456789") && !text.contains("HDFC"), "no plaintext leaks in file")
let opened = try! OpenVault.unlock(file: try! VaultFile.parse(bytes), password: "correct horse", secretKey: sk)
check(opened.payload.items == v.payload.items, "roundtrip equal")
throwsError("wrong password") { _ = try OpenVault.unlock(file: file, password: "wrong", secretKey: sk) }
throwsError("wrong secret key") { _ = try OpenVault.unlock(file: file, password: "correct horse", secretKey: SecretKey.generate()) }
var tampered = file; tampered.header.vaultID = UUID()
throwsError("header tamper") { _ = try OpenVault.unlock(file: tampered, password: "correct horse", secretKey: sk) }
throwsError("garbage parse") { _ = try VaultFile.parse(Data("nope".utf8)) }
let re = try! v.rewrapped(password: "new pass", secretKey: sk, iterations: 1000)
let reFile = try! re.sealed(deviceName: "Mac")
throwsError("old password after change") { _ = try OpenVault.unlock(file: reFile, password: "correct horse", secretKey: sk) }
check((try? OpenVault.unlock(file: reFile, password: "new pass", secretKey: sk))?.payload.items.count == 2, "new password opens, data kept")

print("Merge")
var phone = try! OpenVault.unlock(file: file, password: "correct horse", secretKey: sk)
let t1 = Date().addingTimeInterval(10)
phone.payload.items[0].title = "HDFC Savings (edited)"; phone.payload.items[0].touch(t1)
phone.payload.items[1].markDeleted(at: t1)
phone.payload.items.append(VaultItem(title: "PAN", category: .identity, createdAt: t1, modifiedAt: t1))
var macAgain = v
let summary = try! macAgain.merge(file: try! phone.sealed(deviceName: "iPhone"), password: "correct horse", secretKey: sk)
check(summary.updated == 1 && summary.deleted == 1 && summary.added == 1, "summary \(summary)")
let live = macAgain.payload.liveItems
check(live.count == 2 && live.contains { $0.title == "HDFC Savings (edited)" } && live.contains { $0.title == "PAN" }, "live set after merge")
var phoneAgain = phone; _ = phoneAgain.merge(payload: v.payload)
check(Set(phoneAgain.payload.liveItems.map(\.id)) == Set(live.map(\.id)), "merge is symmetric")
var p = VaultPayload()
var old = VaultItem(title: "x"); old.markDeleted(at: Date().addingTimeInterval(-100 * 86400))
var recent = VaultItem(title: "y"); recent.markDeleted()
p.items = [old, recent]; p.pruneTombstones()
check(p.items.count == 1, "tombstone pruning")

print("Search")
var card = VaultItem(title: "Card", category: .card, fields: Templates.fields(for: .card))
card.fields[1].value = "4111111111111111"; card.fields[4].value = "987"
check(card.searchText.contains("4111") && !card.searchText.contains("987") && card.searchText.contains("cvv"), "secret values excluded")

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)

import Testing
import Foundation
@testable import VaultCore

@Suite struct VaultFileTests {
    let iters = 1000

    func makeVault() throws -> (OpenVault, SecretKey) {
        let sk = SecretKey.generate()
        var v = try OpenVault.create(password: "correct horse", secretKey: sk, deviceName: "Mac", iterations: iters)
        var item = VaultItem(title: "HDFC Savings", category: .bank, fields: Templates.fields(for: .bank))
        item.fields[2].value = "50100123456789"
        v.payload.items.append(item)
        v.payload.items.append(VaultItem(title: "Gmail", category: .login, fields: Templates.fields(for: .login)))
        return (v, sk)
    }

    @Test func createSealUnlockRoundTrip() throws {
        let (v, sk) = try makeVault()
        let file = try v.sealed(deviceName: "Mac")
        let bytes = try file.serialized()
        #expect(bytes.starts(with: VaultFile.magic))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("50100123456789"), "account number must not be in plaintext")
        #expect(!text.contains("HDFC"))
        let parsed = try VaultFile.parse(bytes)
        let opened = try OpenVault.unlock(file: parsed, password: "correct horse", secretKey: sk)
        #expect(opened.payload.items == v.payload.items)
        #expect(opened.payload.liveItems.count == 2)
    }

    @Test func wrongPasswordOrKeyFails() throws {
        let (v, sk) = try makeVault()
        let file = try v.sealed(deviceName: "Mac")
        #expect(throws: VaultError.wrongCredentials) { try OpenVault.unlock(file: file, password: "wrong", secretKey: sk) }
        #expect(throws: VaultError.wrongCredentials) { try OpenVault.unlock(file: file, password: "correct horse", secretKey: SecretKey.generate()) }
    }

    @Test func headerTamperFails() throws {
        let (v, sk) = try makeVault()
        var file = try v.sealed(deviceName: "Mac")
        file.header.vaultID = UUID()
        #expect(throws: VaultError.wrongCredentials) { try OpenVault.unlock(file: file, password: "correct horse", secretKey: sk) }
    }

    @Test func parseRejectsGarbage() {
        #expect(throws: VaultError.unsupportedFormat) { try VaultFile.parse(Data("nope".utf8)) }
        #expect(throws: VaultError.corruptFile) { try VaultFile.parse(VaultFile.magic + Data("{}".utf8)) }
    }

    @Test func passwordChangeKeepsData() throws {
        let (v, sk) = try makeVault()
        let re = try v.rewrapped(password: "new pass", secretKey: sk, iterations: iters)
        let file = try re.sealed(deviceName: "Mac")
        #expect(throws: VaultError.wrongCredentials) { try OpenVault.unlock(file: file, password: "correct horse", secretKey: sk) }
        let opened = try OpenVault.unlock(file: file, password: "new pass", secretKey: sk)
        #expect(opened.payload.items.count == 2)
    }

    @Test func mergeNewerWinsAndTombstonesPropagate() throws {
        let (mac, sk) = try makeVault()
        var phone = try OpenVault.unlock(file: try mac.sealed(deviceName: "Mac"), password: "correct horse", secretKey: sk)
        let t1 = Date().addingTimeInterval(10)
        phone.payload.items[0].title = "HDFC Savings (edited)"; phone.payload.items[0].touch(t1)
        phone.payload.items[1].markDeleted(at: t1)
        phone.payload.items.append(VaultItem(title: "PAN", category: .identity, createdAt: t1, modifiedAt: t1))
        var macAgain = mac
        let summary = try macAgain.merge(file: try phone.sealed(deviceName: "iPhone"), password: "correct horse", secretKey: sk)
        #expect(summary.updated == 1)
        #expect(summary.deleted == 1)
        #expect(summary.added == 1)
        let live = macAgain.payload.liveItems
        #expect(live.count == 2)
        #expect(live.contains { $0.title == "HDFC Savings (edited)" })
        #expect(live.contains { $0.title == "PAN" })
        var phoneAgain = phone
        _ = phoneAgain.merge(payload: mac.payload)
        #expect(Set(phoneAgain.payload.liveItems.map(\.id)) == Set(live.map(\.id)))
    }

    @Test func tombstonePruning() {
        var p = VaultPayload()
        var old = VaultItem(title: "x"); old.markDeleted(at: Date().addingTimeInterval(-100 * 86400))
        var recent = VaultItem(title: "y"); recent.markDeleted()
        p.items = [old, recent]
        p.pruneTombstones()
        #expect(p.items.count == 1)
    }

    @Test func searchExcludesSecretValues() {
        var item = VaultItem(title: "Card", category: .card, fields: Templates.fields(for: .card))
        item.fields[1].value = "4111111111111111"
        item.fields[4].value = "987"
        #expect(item.searchText.contains("4111"))
        #expect(!item.searchText.contains("987"))
        #expect(item.searchText.contains("cvv"))
    }
}

import SwiftUI
import Combine
import CryptoKit
import VaultCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum Module: Hashable { case cards, sync, settings }

public enum SetupStep: Hashable { case password, keyCard, biometrics, code, done }

public enum Phase: Hashable {
    case loading
    case welcome                 // no vault on this device
    case setup(SetupStep)        // creating a new vault
    case adopt                   // importing an existing vault file onto this device
    case locked
    case code                    // decrypted, waiting for the one-time code
    case unlocked
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public var phase: Phase = .loading
    @Published public var module: Module = .cards
    @Published public var status: String?
    @Published public var statusIsError = false
    @Published public var busy = false
    @Published public private(set) var vault: OpenVault?
    @Published public var selectedItemID: UUID?
    @Published public var editingItem: VaultItem?
    @Published public var pendingImportURL: URL?
    @Published public var lastSavedAt: Date?
    @Published public var lastImport: (Date, MergeSummary)?

    // Setup scratch (cleared when setup ends)
    @Published public var setupSecretKey: SecretKey?
    @Published public var setupTOTP: TOTP?
    public var setupPassword = ""

    @AppStorage("autoLockSeconds") public var autoLockSeconds: Int = 120
    @AppStorage("deviceName") public var deviceName: String = AppModel.defaultDeviceName()

    public let store: LocalStore
    private var lockedFile: VaultFile?
    private var autoLockTask: Task<Void, Never>?
    private var clipboardTask: Task<Void, Never>?
    private var pendingVault: OpenVault?   // decrypted but gated behind the one-time code

    public init(store: LocalStore = LocalStore()) {
        self.store = store
        Fonts.register()
        reload()
    }

    public var vaultID: UUID? { (vault ?? pendingVault)?.header.vaultID ?? lockedFile?.header.vaultID }
    public var items: [VaultItem] { vault?.payload.liveItems ?? [] }

    public func reload() {
        do {
            lockedFile = try store.load()
            phase = lockedFile == nil ? .welcome : .locked
        } catch {
            lockedFile = nil
            phase = .welcome
            setStatus("Vault file could not be read", error: true)
        }
    }

    public func setStatus(_ s: String?, error: Bool = false) { status = s; statusIsError = error }

    // MARK: Unlock

    /// Password + biometrics (releases the secret key) → decrypt → one-time code gate.
    public func unlock(password: String) {
        guard let file = lockedFile, !busy else { return }
        busy = true; setStatus("Checking")
        Task {
            do {
                let key = try DeviceKeychain.loadSecretKey(vaultID: file.header.vaultID, reason: "Unlock VAULT")
                try await finishUnlock(file: file, password: password, secretKey: key)
            } catch VaultError.notEnrolled {
                setStatus("This device is not enrolled. Enter the secret key.", error: true)
                needsTypedKey = true
            } catch VaultError.biometricsCancelled {
                setStatus(nil)
            } catch {
                setStatus(error.localizedDescription, error: true)
            }
            busy = false
        }
    }

    @Published public var needsTypedKey = false

    /// Fallback when biometrics are unavailable: the printed key card.
    public func unlock(password: String, typedKey: String) {
        guard let file = lockedFile, !busy else { return }
        busy = true; setStatus("Checking")
        Task {
            do {
                let key = try SecretKey(parsing: typedKey)
                try await finishUnlock(file: file, password: password, secretKey: key)
                // Re-enrol this device if biometrics are available now.
                if DeviceKeychain.availableBiometry() != .none {
                    try? DeviceKeychain.storeSecretKey(key, vaultID: file.header.vaultID)
                }
                needsTypedKey = false
            } catch {
                setStatus(error is VaultError ? error.localizedDescription : "Incorrect password", error: true)
            }
            busy = false
        }
    }

    private func finishUnlock(file: VaultFile, password: String, secretKey: SecretKey) async throws {
        let opened = try await Task.detached(priority: .userInitiated) {
            try OpenVault.unlock(file: file, password: password, secretKey: secretKey)
        }.value
        setStatus(nil)
        if opened.payload.totpSecret != nil {
            pendingVault = opened
            phase = .code
        } else {
            enterUnlocked(opened)
        }
    }

    public func verifyCode(_ code: String) {
        guard let pv = pendingVault, let seed = pv.payload.totpSecret else { return }
        let totp = TOTP(secret: seed)
        guard let counter = totp.validate(code) else { setStatus("Incorrect code", error: true); return }
        let id = pv.header.vaultID
        guard counter > DeviceKeychain.lastAcceptedCounter(vaultID: id) else { setStatus("Code already used", error: true); return }
        DeviceKeychain.setLastAcceptedCounter(counter, vaultID: id)
        enterUnlocked(pv)
    }

    private func enterUnlocked(_ v: OpenVault) {
        pendingVault = nil
        vault = v
        setStatus(nil)
        phase = .unlocked
        module = .cards
        touchActivity()
    }

    public func lock() {
        autoLockTask?.cancel()
        vault = nil
        pendingVault = nil
        selectedItemID = nil
        editingItem = nil
        setStatus(nil)
        phase = lockedFile == nil ? .welcome : .locked
    }

    public func touchActivity() {
        autoLockTask?.cancel()
        guard phase == .unlocked || phase == .code, autoLockSeconds > 0 else { return }
        let secs = autoLockSeconds
        autoLockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lock()
        }
    }

    // MARK: Setup: new vault

    public func beginSetup() {
        setupPassword = ""; setupSecretKey = SecretKey.generate(); setupTOTP = TOTP.generateSecret()
        setStatus(nil); phase = .setup(.password)
    }

    public func setupChoosePassword(_ pw: String, confirm: String) {
        let n = KeyDerivation.normalize(password: pw)
        guard n.count >= 12 else { setStatus("Use at least 12 characters", error: true); return }
        guard pw == confirm else { setStatus("Passwords do not match", error: true); return }
        setupPassword = pw; setStatus(nil); phase = .setup(.keyCard)
    }

    public func setupKeyCardSaved() { setStatus(nil); phase = .setup(.biometrics) }

    public func setupEnrolBiometrics() {
        // The vault is created now so the secret key can be bound to its id.
        guard let sk = setupSecretKey else { return }
        busy = true; setStatus("Creating vault")
        let pw = setupPassword, name = deviceName, totp = setupTOTP
        Task {
            do {
                var v = try await Task.detached(priority: .userInitiated) {
                    try OpenVault.create(password: pw, secretKey: sk, deviceName: name)
                }.value
                v.payload.totpSecret = totp?.secret
                try DeviceKeychain.storeSecretKey(sk, vaultID: v.header.vaultID)
                vault = v
                try persist()
                setStatus(nil)
                phase = .setup(.code)
            } catch {
                setStatus(error.localizedDescription, error: true)
            }
            busy = false
        }
    }

    public func setupConfirmCode(_ code: String) {
        guard let totp = setupTOTP, let v = vault else { return }
        guard let c = totp.validate(code) else { setStatus("Incorrect code. Check the authenticator entry.", error: true); return }
        DeviceKeychain.setLastAcceptedCounter(c, vaultID: v.header.vaultID)
        setStatus(nil)
        phase = .setup(.done)
    }

    public func setupFinish() {
        setupPassword = ""; setupSecretKey = nil; setupTOTP = nil
        guard let v = vault else { phase = .welcome; return }
        enterUnlocked(v)
    }

    // MARK: Adopt an existing vault file on a new device

    public func adopt(fileURL: URL, password: String, typedKey: String) {
        busy = true; setStatus("Checking")
        Task {
            do {
                let accessed = fileURL.startAccessingSecurityScopedResource()
                defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                let file = try VaultFile.parse(try Data(contentsOf: fileURL))
                let key = try SecretKey(parsing: typedKey)
                let opened = try await Task.detached(priority: .userInitiated) {
                    try OpenVault.unlock(file: file, password: password, secretKey: key)
                }.value
                try store.save(file)
                lockedFile = file
                if DeviceKeychain.availableBiometry() != .none {
                    try DeviceKeychain.storeSecretKey(key, vaultID: file.header.vaultID)
                }
                pendingImportURL = nil
                setStatus(nil)
                if opened.payload.totpSecret != nil { pendingVault = opened; phase = .code } else { enterUnlocked(opened) }
            } catch {
                setStatus(error.localizedDescription, error: true)
            }
            busy = false
        }
    }

    // MARK: Items

    public func upsert(_ item: VaultItem) {
        guard var v = vault else { return }
        var it = item; it.touch()
        if let i = v.payload.items.firstIndex(where: { $0.id == it.id }) { v.payload.items[i] = it } else { v.payload.items.insert(it, at: 0) }
        vault = v
        try? persist()
        touchActivity()
    }

    public func delete(_ id: UUID) {
        guard var v = vault, let i = v.payload.items.firstIndex(where: { $0.id == id }) else { return }
        v.payload.items[i].markDeleted()
        vault = v
        if selectedItemID == id { selectedItemID = nil }
        try? persist()
    }

    public func item(_ id: UUID?) -> VaultItem? { id.flatMap { id in items.first { $0.id == id } } }

    private func persist() throws {
        guard let v = vault else { return }
        let file = try v.sealed(deviceName: deviceName)
        try store.save(file)
        lockedFile = file
        lastSavedAt = file.header.modifiedAt
    }

    // MARK: Sync by file

    public func exportData() throws -> Data {
        guard let file = lockedFile else { throw VaultError.notEnrolled }
        return try file.serialized()
    }

    public var exportFilename: String { "VAULT-\(Fmt.stamp(Date())).vault" }

    /// Merge another copy of this vault. Same vault id is required; the secret key is already known.
    public func importAndMerge(fileURL: URL, password: String) {
        guard var v = vault else { return }
        busy = true; setStatus("Checking")
        Task {
            do {
                let accessed = fileURL.startAccessingSecurityScopedResource()
                defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                let incoming = try VaultFile.parse(try Data(contentsOf: fileURL))
                guard incoming.header.vaultID == v.header.vaultID else {
                    setStatus("That file belongs to a different vault", error: true); busy = false; return
                }
                let key = try DeviceKeychain.loadSecretKey(vaultID: v.header.vaultID, reason: "Import into VAULT")
                let summary = try await Task.detached(priority: .userInitiated) { () -> MergeSummary in
                    try v.merge(file: incoming, password: password, secretKey: key)
                }.value
                vault = v
                try persist()
                lastImport = (Date(), summary)
                pendingImportURL = nil
                setStatus("Merged: \(summary.added) added, \(summary.updated) updated, \(summary.deleted) deleted")
            } catch {
                setStatus(error.localizedDescription, error: true)
            }
            busy = false
        }
    }

    public func handleIncoming(url: URL) {
        pendingImportURL = url
        if phase == .welcome { phase = .adopt } else if phase == .unlocked { module = .sync }
    }

    // MARK: Settings

    public func changePassword(current: String, new: String, confirm: String) {
        guard let v = vault else { return }
        guard KeyDerivation.normalize(password: new).count >= 12 else { setStatus("Use at least 12 characters", error: true); return }
        guard new == confirm else { setStatus("Passwords do not match", error: true); return }
        busy = true; setStatus("Checking")
        let file = lockedFile
        Task {
            do {
                let key = try DeviceKeychain.loadSecretKey(vaultID: v.header.vaultID, reason: "Change VAULT password")
                guard let file else { throw VaultError.corruptFile }
                let re = try await Task.detached(priority: .userInitiated) { () -> OpenVault in
                    _ = try OpenVault.unlock(file: file, password: current, secretKey: key)   // proves the current password
                    return try v.rewrapped(password: new, secretKey: key)
                }.value
                vault = re
                try persist()
                setStatus("Password changed")
            } catch { setStatus(error.localizedDescription, error: true) }
            busy = false
        }
    }

    /// Shows the key card again. Biometrics required.
    public func revealSecretKey() -> SecretKey? {
        guard let id = vaultID else { return nil }
        return try? DeviceKeychain.loadSecretKey(vaultID: id, reason: "Show VAULT secret key")
    }

    public func resetOneTimeCode() -> TOTP? {
        guard var v = vault else { return nil }
        let t = TOTP.generateSecret()
        v.payload.totpSecret = t.secret
        vault = v
        try? persist()
        return t
    }

    public func wipeThisDevice() {
        if let id = vaultID { DeviceKeychain.wipe(vaultID: id) }
        store.wipe()
        vault = nil; pendingVault = nil; lockedFile = nil
        phase = .welcome
    }

    // MARK: Clipboard (clears after 30 s)

    public func copy(_ text: String, secret: Bool) {
        #if canImport(UIKit)
        if secret {
            UIPasteboard.general.setItems([[UTTypeText: text]], options: [.expirationDate: Date().addingTimeInterval(30), .localOnly: true])
        } else { UIPasteboard.general.string = text }
        #else
        let pb = NSPasteboard.general
        pb.clearContents()
        if secret { pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
        pb.setString(text, forType: .string)
        #endif
        setStatus(secret ? "Copied. Clears in 30 s" : "Copied")
        clipboardTask?.cancel()
        clipboardTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            #if canImport(AppKit)
            if secret, NSPasteboard.general.string(forType: .string) == text { NSPasteboard.general.clearContents() }
            #endif
            await MainActor.run { if self?.status?.hasPrefix("Copied") == true { self?.setStatus(nil) } }
        }
        touchActivity()
    }

    /// Previews and screenshots only: show an already-open vault without touching the keychain.
    public func loadForPreview(_ v: OpenVault, phase: Phase = .unlocked) {
        vault = v; lockedFile = try? v.sealed(deviceName: deviceName); lastSavedAt = Date(); self.phase = phase
    }

    public static func defaultDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}

#if canImport(UIKit)
private let UTTypeText = "public.utf8-plain-text"
#endif

import SwiftUI
import VaultUI
import VaultCore
#if canImport(AppKit)
import AppKit
#endif

@main
struct VaultApp: App {
    @StateObject private var model = AppModel()

    init() { Self.runKeychainSelfTestIfRequested() }

    var body: some Scene {
        WindowGroup("VAULT") {
            RootView(model: model)
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 680)
                .onAppear { hardenWindows() }
                #endif
        }
        #if os(macOS)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Vault") {
                Button("Lock") { model.lock() }.keyboardShortcut("l", modifiers: .command)
            }
        }
        #endif
    }

    #if DEBUG
    /// `--keychain-selftest`: exercises the biometric keychain path end to end and exits.
    /// Debug builds only. Used from the Simulator with simulated Face ID.
    static func runKeychainSelfTestIfRequested() {
        guard CommandLine.arguments.contains("--keychain-selftest") else { return }
        Task.detached {
            var lines: [String] = []
            func print(_ s: String) { lines.append(s); NSLog("%@", s) }
            defer {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("selftest.txt")
                try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            let id = UUID(), sk = SecretKey.generate()
            print("SELFTEST: biometry=\(DeviceKeychain.availableBiometry())")
            do {
                try DeviceKeychain.storeSecretKey(sk, vaultID: id)
                print("SELFTEST: store secret key ok, enrolled=\(DeviceKeychain.hasSecretKey(vaultID: id))")
                let back = try DeviceKeychain.loadSecretKey(vaultID: id, reason: "Self test")
                print("SELFTEST: load secret key \(back == sk ? "ok" : "MISMATCH")")
                try DeviceKeychain.storeTOTP(TOTP.generateSecret(), vaultID: id)
                print("SELFTEST: totp \(try DeviceKeychain.loadTOTP(vaultID: id) != nil ? "ok" : "nil")")
                DeviceKeychain.setLastAcceptedCounter(42, vaultID: id)
                print("SELFTEST: counter \(DeviceKeychain.lastAcceptedCounter(vaultID: id) == 42 ? "ok" : "bad")")
                DeviceKeychain.wipe(vaultID: id)
                print("SELFTEST: DONE")
            } catch {
                print("SELFTEST: FAIL \(error)")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            exit(0)
        }
    }
    #else
    static func runKeychainSelfTestIfRequested() {}
    #endif

    #if os(macOS)
    /// Window contents are excluded from screen capture and screen sharing.
    private func hardenWindows() {
        DispatchQueue.main.async {
            for w in NSApplication.shared.windows {
                w.sharingType = .none
                w.titlebarAppearsTransparent = true
                w.backgroundColor = NSColor(red: 13/255, green: 13/255, blue: 13/255, alpha: 1)
            }
        }
    }
    #endif
}

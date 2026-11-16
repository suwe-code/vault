// Captures every screen from a real AppKit window (so text fields and scroll views render)
// without touching the keychain. Usage: swift run VaultPreview <output-dir>
import SwiftUI
import AppKit
import VaultCore
import VaultUI

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./previews")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

@MainActor
func sample() -> OpenVault {
    let sk = SecretKey.generate()
    var v = try! OpenVault.create(password: "sample sample sample", secretKey: sk, deviceName: "MacBook Air", iterations: 1000)
    var bank = VaultItem(title: "HDFC Savings", category: .bank, fields: Templates.fields(for: .bank), favourite: true)
    let bankVals = ["HDFC Bank", "Suwetha Parker", "50100123456789", "HDFC0001234", "88123456", "Koramangala", "suwe.hdfc", "hunter2hunter2", "4821", "7719", "+91 98450 00000"]
    for (i, s) in bankVals.enumerated() { bank.fields[i].value = s }
    bank.notes = "Salary account. Cheque book in the grey folder."
    bank.tags = ["salary", "primary"]
    var card = VaultItem(title: "HDFC Regalia", category: .card, fields: Templates.fields(for: .card))
    for (i, s) in ["HDFC Bank", "4111 1111 1111 1111", "SUWETHA PARKER", "09/28", "123", "9090", "HDFC Savings"].enumerated() { card.fields[i].value = s }
    var gmail = VaultItem(title: "Gmail", category: .login, fields: Templates.fields(for: .login))
    for (i, s) in ["https://mail.google.com", "suwethaparker@gmail.com", "correct-horse-battery", "JBSWY3DPEHPK3PXP", "", "+91 98450 00000", "8821 0931 7712 5540"].enumerated() { gmail.fields[i].value = s }
    var pan = VaultItem(title: "PAN", category: .identity, fields: Templates.fields(for: .identity))
    for (i, s) in ["PAN card", "ABCDE1234F", "SUWETHA PARKER", "1996-04-12"].enumerated() { pan.fields[i].value = s }
    let note = VaultItem(title: "Locker", category: .note, notes: "Locker 214 at the Indiranagar branch. Key in the desk drawer.")
    v.payload.items = [bank, card, gmail, pan, note]
    return v
}

@MainActor
func sampleMedia() -> [MediaEntry] {
    // A flat colour JPEG stands in for a photo.
    let img = NSImage(size: NSSize(width: 320, height: 200)); img.lockFocus()
    NSColor(red: 0.35, green: 0.45, blue: 0.4, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 320, height: 200).fill()
    NSColor(red: 0.8, green: 0.75, blue: 0.6, alpha: 1).setFill(); NSRect(x: 40, y: 30, width: 200, height: 110).fill()
    img.unlockFocus()
    let jpeg = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .jpeg, properties: [:])
    return [
        MediaEntry(name: "passport-scan.jpg", type: "public.jpeg", size: 2_310_000, thumbnail: jpeg),
        MediaEntry(name: "Aadhaar.pdf", type: "com.adobe.pdf", size: 412_000),
        MediaEntry(name: "house-walkthrough.mov", type: "com.apple.quicktime-movie", size: 188_000_000),
        MediaEntry(name: "keys-backup.zip", type: "public.zip-archive", size: 9_400),
        MediaEntry(name: "IMG_4411.heic", type: "public.heic", size: 3_100_000, thumbnail: jpeg),
    ]
}

struct Scenario { let name: String; let size: CGSize; let phone: Bool; let prepare: @MainActor () -> AnyView }

@MainActor
func scenarios() -> [Scenario] {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vault-preview-\(UUID().uuidString)")
    let mac = CGSize(width: 1100, height: 760), ph = CGSize(width: 390, height: 844)
    func model(_ setup: @escaping (AppModel) -> Void) -> @MainActor () -> AnyView {
        return { let m = AppModel(store: LocalStore(directory: tmp)); setup(m); return AnyView(RootView(model: m)) }
    }
    let v = sample()
    return [
        Scenario(name: "01-mac-lock", size: mac, phone: false, prepare: model { $0.phase = .locked }),
        Scenario(name: "01-phone-lock", size: ph, phone: true, prepare: model { $0.phase = .locked }),
        Scenario(name: "02-mac-lock-error", size: mac, phone: false, prepare: model { $0.phase = .locked; $0.needsTypedKey = true; $0.setStatus("Incorrect password or secret key", error: true) }),
        Scenario(name: "03-mac-welcome", size: mac, phone: false, prepare: model { $0.phase = .welcome }),
        Scenario(name: "04-mac-setup-password", size: mac, phone: false, prepare: model { $0.beginSetup() }),
        Scenario(name: "05-mac-setup-keycard", size: mac, phone: false, prepare: model { $0.beginSetup(); $0.phase = .setup(.keyCard) }),
        Scenario(name: "05-phone-setup-keycard", size: ph, phone: true, prepare: model { $0.beginSetup(); $0.phase = .setup(.keyCard) }),
        Scenario(name: "06-mac-setup-biometrics", size: mac, phone: false, prepare: model { $0.beginSetup(); $0.phase = .setup(.biometrics) }),
        Scenario(name: "08-mac-setup-done", size: mac, phone: false, prepare: model { $0.beginSetup(); $0.phase = .setup(.done) }),
        Scenario(name: "09-mac-adopt", size: mac, phone: false, prepare: model { $0.phase = .adopt }),
        Scenario(name: "11-mac-cards", size: mac, phone: false, prepare: model { $0.loadForPreview(v) }),
        Scenario(name: "11-phone-cards", size: ph, phone: true, prepare: model { $0.loadForPreview(v) }),
        Scenario(name: "13b-mac-editor", size: mac, phone: false, prepare: model { $0.loadForPreview(v); $0.editingItem = v.payload.items[2] }),
        Scenario(name: "13b-phone-editor", size: CGSize(width: 390, height: 1100), phone: true, prepare: model { $0.loadForPreview(v); $0.editingItem = v.payload.items[2] }),
        Scenario(name: "12-mac-files", size: CGSize(width: 660, height: 500), phone: false, prepare: model { $0.loadForPreview(v); $0.module = .files; $0.media = sampleMedia() }),
        Scenario(name: "12-phone-files", size: ph, phone: true, prepare: model { $0.loadForPreview(v); $0.module = .files; $0.media = sampleMedia() }),
        Scenario(name: "12-mac-files-empty", size: CGSize(width: 660, height: 500), phone: false, prepare: model { $0.loadForPreview(v); $0.module = .files }),
        Scenario(name: "14-mac-sync", size: mac, phone: false, prepare: model { $0.loadForPreview(v); $0.module = .sync }),
        Scenario(name: "14-phone-sync", size: ph, phone: true, prepare: model { $0.loadForPreview(v); $0.module = .sync }),
        Scenario(name: "15-mac-settings", size: CGSize(width: 1100, height: 1150), phone: false, prepare: model { $0.loadForPreview(v); $0.module = .settings }),
        Scenario(name: "15-phone-settings", size: CGSize(width: 390, height: 1400), phone: true, prepare: model { $0.loadForPreview(v); $0.module = .settings }),
    ]
}

@MainActor
final class Runner: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var host: NSHostingView<AnyView>!
    var queue: [Scenario] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Fonts.register()
        queue = scenarios()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        host = NSHostingView(rootView: AnyView(EmptyView()))
        window.contentView = host
        window.orderFrontRegardless()
        next()
    }

    func next() {
        guard !queue.isEmpty else { print("done"); NSApp.terminate(nil); return }
        let sc = queue.removeFirst()
        Type.phoneOverride = sc.phone
        window.setContentSize(sc.size)
        host.rootView = AnyView(sc.prepare().frame(width: sc.size.width, height: sc.size.height))
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
            capture(sc.name)
            next()
        }
    }

    func capture(_ name: String) {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("FAILED \(name)"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
        print("wrote \(name).png")
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let runner = Runner()
    app.delegate = runner
    app.run()
}

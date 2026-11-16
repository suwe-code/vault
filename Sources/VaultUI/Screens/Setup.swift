import SwiftUI
import VaultCore

struct SetupScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Gate(width: 420) {
            switch model.phase {
            case .setup(.password): PasswordStep(model: model)
            case .setup(.keyCard): KeyCardStep(model: model)
            case .setup(.biometrics): BiometricsStep(model: model)
            case .setup(.done): DoneStep(model: model)
            default: EmptyView()
            }
        }
    }
}

private struct StepHeader: View {
    let n: Int, title: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tok.s3) {
            Tag("\(n) / 4")
            Text(title).font(Type.title3()).foregroundStyle(Tok.text)
        }
    }
}

struct PasswordStep: View {
    @ObservedObject var model: AppModel
    @State private var pw = ""
    @State private var confirm = ""
    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            StepHeader(n: 1, title: "Master password")
            Text("The only thing you memorise. There is no reset: if it is lost the vault is lost. Four or five unrelated words work well.")
                .font(Type.body()).foregroundStyle(Tok.text2)
            OpsField("Password", text: $pw, style: .secure, hint: "At least 12 characters", autofocus: true)
            OpsField("Confirm", text: $confirm, style: .secure, onSubmit: go)
            StatusLine(model.status, isError: model.statusIsError)
            HStack(spacing: Tok.s1) {
                OpsButton("Continue", kind: .primary, disabled: pw.isEmpty || confirm.isEmpty, action: go)
                OpsButton("Cancel") { model.phase = .welcome }
            }
        }
    }
    private func go() { model.setupChoosePassword(pw, confirm: confirm) }
}

struct KeyCardStep: View {
    @ObservedObject var model: AppModel
    @State private var lastGroup = ""
    @State private var exporting = false
    var key: SecretKey { model.setupSecretKey ?? SecretKey.generate() }
    var expected: String { String(key.formatted.suffix(4)) }
    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            StepHeader(n: 2, title: "Secret key")
            Text("The second factor. Combined with the password to encrypt the vault, so a stolen file cannot be cracked without it. Keep it on paper, away from your devices. It is never stored inside the vault file.")
                .font(Type.body()).foregroundStyle(Tok.text2)
            KeyCard(key: key)
            HStack(spacing: Tok.s1) {
                OpsButton("Copy") { model.copy(key.formatted, secret: false) }
                OpsButton("Save as text") { exporting = true }
            }
            OpsField("Type the last group to confirm", text: $lastGroup, style: .mono, placeholder: "XXXX", onSubmit: go)
            StatusLine(model.status, isError: model.statusIsError)
            OpsButton("Continue", kind: .primary, disabled: lastGroup.uppercased() != expected, action: go)
        }
        .fileExporter(isPresented: $exporting, document: TextExportDocument(text: "VAULT secret key\n\(key.formatted)\n\nKeep with the master password in your head, never together on a device.\n"),
                      contentType: .plainText, defaultFilename: "VAULT-secret-key") { _ in }
    }
    private func go() { if lastGroup.uppercased() == expected { model.setupKeyCardSaved() } }
}

/// Recessed well, data-lg mono, groups wrap on phones.
struct KeyCard: View {
    let key: SecretKey
    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s2) {
            Lbl("Key card")
            Text(key.formatted).font(Type.dataLg()).foregroundStyle(Tok.text)
                .textSelection(.enabled).lineLimit(3).minimumScaleFactor(0.6)
        }
        .padding(Tok.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.recessed)
        .overlay(Rectangle().stroke(Tok.border, lineWidth: 1))
    }
}

struct BiometricsStep: View {
    @ObservedObject var model: AppModel
    var bio: DeviceKeychain.Biometry { DeviceKeychain.availableBiometry() }
    var name: String {
        switch bio { case .faceID: return "Face ID"; case .touchID: return "Touch ID"; case .opticID: return "Optic ID"; case .none: return "biometrics" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            StepHeader(n: 3, title: "This device")
            if bio == .none {
                Text("No biometrics are available on this device, so the secret key will have to be typed at every unlock. Enable Touch ID or Face ID in system settings and set up again if you want it released automatically.")
                    .font(Type.body()).foregroundStyle(Tok.text2)
            } else {
                Text("The secret key is placed in this device's keychain behind \(name). Every unlock then needs \(name) and the password. If \(name) is re-enrolled the key is discarded and the key card is needed again.")
                    .font(Type.body()).foregroundStyle(Tok.text2)
            }
            StatusLine(model.status, isError: model.statusIsError)
            OpsButton("Create vault", kind: .primary, disabled: model.busy) { model.setupEnrolBiometrics() }
        }
    }
}

struct DoneStep: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            StepHeader(n: 4, title: "Ready")
            VStack(spacing: 0) {
                row("Password", "SET"); Rule(quiet: true)
                row("Secret key", "ON PAPER"); Rule(quiet: true)
                row("This device", DeviceKeychain.availableBiometry() == .none ? "TYPED KEY" : "ENROLLED")
            }
            Text("To add your iPhone later: Sync, Export file, AirDrop it, then Import vault file on the phone with the password and the key card.")
                .font(Type.body()).foregroundStyle(Tok.text2)
            OpsButton("Open vault", kind: .primary) { model.setupFinish() }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(Type.cell()).foregroundStyle(Tok.text2); Spacer(); StatusMark(.confirmed, v) }
            .padding(.vertical, Tok.s25)
    }
}

// MARK: Adopt an existing vault

struct AdoptScreen: View {
    @ObservedObject var model: AppModel
    @State private var picking = false
    @State private var password = ""
    @State private var typedKey = ""
    var body: some View {
        Gate(width: 420) {
            VStack(alignment: .leading, spacing: Tok.s4) {
                Text("Import vault file").font(Type.title3()).foregroundStyle(Tok.text)
                Text("Choose the file exported from your other device. Opening it needs the master password and the secret key from the key card. This device is then enrolled.")
                    .font(Type.body()).foregroundStyle(Tok.text2)
                HStack(spacing: Tok.s3) {
                    OpsButton("Choose file") { picking = true }
                    Text(model.pendingImportURL?.lastPathComponent ?? "No file chosen").font(Type.data()).foregroundStyle(Tok.text2).lineLimit(1)
                }
                OpsField("Password", text: $password, style: .secure)
                OpsField("Secret key", text: $typedKey, style: .mono, placeholder: "VK1-", onSubmit: go)
                StatusLine(model.status, isError: model.statusIsError)
                HStack(spacing: Tok.s1) {
                    OpsButton("Unlock", kind: .primary, disabled: model.pendingImportURL == nil || password.isEmpty || typedKey.isEmpty || model.busy, action: go)
                    OpsButton("Back") { model.pendingImportURL = nil; model.setStatus(nil); model.phase = .welcome }
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.vaultFile]) { r in
            if case .success(let url) = r { model.pendingImportURL = url }
        }
    }
    private func go() { if let url = model.pendingImportURL { model.adopt(fileURL: url, password: password, typedKey: typedKey) } }
}

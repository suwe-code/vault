import SwiftUI
import VaultCore

struct SyncModule: View {
    @ObservedObject var model: AppModel
    @State private var exporting = false
    @State private var exportDoc: VaultExportDocument?
    @State private var shareURL: URL?
    @State private var picking = false
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tok.s6) {
                KPIStrip([
                    ("Cards", "\(model.items.count)", nil),
                    ("Last saved", model.lastSavedAt.map(Fmt.stamp) ?? "-", model.deviceName),
                    ("Last import", model.lastImport.map { Fmt.stamp($0.0) } ?? "-",
                     model.lastImport.map { "\($0.1.added) added, \($0.1.updated) updated, \($0.1.deleted) deleted" }),
                ])

                Panel(title: "Export") {
                    Text("Writes an encrypted copy of this vault. AirDrop it to the other device. Nothing in it can be read without the password and the secret key together.")
                        .font(Type.body()).foregroundStyle(Tok.text2)
                    HStack(spacing: Tok.s1) {
                        if let url = shareURL {
                            ShareLink(item: url) { Lbl("Share", color: Tok.segOnText).padding(.horizontal, Type.isPhone ? 14 : 6).frame(height: Type.isPhone ? Tok.touchHeight : Tok.buttonHeight).background(Tok.segOn) }
                                .buttonStyle(.plain)
                        } else {
                            OpsButton("Prepare file", kind: .primary) { prepareShare() }
                        }
                        OpsButton("Save file") { exportDoc = (try? model.exportData()).map(VaultExportDocument.init); exporting = exportDoc != nil }
                    }
                    if let url = shareURL { Text(url.lastPathComponent).font(Type.tag()).foregroundStyle(Tok.text3) }
                }

                Panel(title: "Import") {
                    Text("Merges a copy of this vault from another device. Newer edits win per card. Deletions carry over. The other file is left unchanged.")
                        .font(Type.body()).foregroundStyle(Tok.text2)
                    HStack(spacing: Tok.s3) {
                        OpsButton("Choose file") { picking = true }
                        Text(model.pendingImportURL?.lastPathComponent ?? "No file chosen").font(Type.data()).foregroundStyle(Tok.text2).lineLimit(1)
                    }
                    if model.pendingImportURL != nil {
                        HStack(alignment: .bottom, spacing: Tok.s1) {
                            OpsField("Password", text: $password, style: .secure, onSubmit: merge).frame(maxWidth: 320)
                            RowButton("Merge", kind: .primary, disabled: password.isEmpty || model.busy, action: merge)
                        }
                    }
                    StatusLine(model.status, isError: model.statusIsError)
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .vaultFile, defaultFilename: model.exportFilename) { r in
            if case .success = r { model.setStatus("Saved") }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.vaultFile, .data]) { r in
            if case .success(let url) = r { model.pendingImportURL = url; model.setStatus(nil) }
        }
        .onDisappear { if let u = shareURL { try? FileManager.default.removeItem(at: u) } }
    }

    private func prepareShare() {
        guard let data = try? model.exportData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(model.exportFilename)
        do { try data.write(to: url, options: [.atomic, .completeFileProtection]); shareURL = url } catch { model.setStatus("Could not write file", error: true) }
    }

    private func merge() {
        guard let url = model.pendingImportURL else { return }
        model.importAndMerge(fileURL: url, password: password)
        password = ""
    }
}

struct SettingsModule: View {
    @ObservedObject var model: AppModel
    @State private var current = ""
    @State private var newPw = ""
    @State private var confirm = ""
    @State private var shownKey: SecretKey?
    @State private var wipeArmed = false
    @State private var deviceName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tok.s6) {
                Panel(title: "Lock") {
                    if Type.isPhone {
                        Lbl("Auto-lock after")
                        Segmented([(60, "1 min"), (120, "2 min"), (300, "5 min"), (900, "15 min")], selection: $model.autoLockSeconds)
                        OpsButton("Lock now") { model.lock() }
                    } else {
                        HStack(spacing: Tok.s3) {
                            Lbl("Auto-lock after")
                            Segmented([(60, "1 min"), (120, "2 min"), (300, "5 min"), (900, "15 min")], selection: $model.autoLockSeconds)
                            Spacer()
                            OpsButton("Lock now") { model.lock() }
                        }
                    }
                    Text("Also locks when the app goes to the background.").font(Type.hint()).foregroundStyle(Tok.text3)
                }

                Panel(title: "Password") {
                    OpsField("Current", text: $current, style: .secure)
                    OpsField("New", text: $newPw, style: .secure, hint: "At least 12 characters")
                    OpsField("Confirm", text: $confirm, style: .secure)
                    HStack {
                        OpsButton("Change password", disabled: current.isEmpty || newPw.isEmpty || confirm.isEmpty || model.busy) {
                            model.changePassword(current: current, new: newPw, confirm: confirm)
                            current = ""; newPw = ""; confirm = ""
                        }
                        StatusLine(model.status, isError: model.statusIsError)
                    }
                }

                Panel(title: "Secret key") {
                    Text("Needed with the password on every new device. Showing it asks for biometrics.").font(Type.body()).foregroundStyle(Tok.text2)
                    if let k = shownKey {
                        KeyCard(key: k)
                        HStack(spacing: Tok.s1) {
                            OpsButton("Copy") { model.copy(k.formatted, secret: true) }
                            OpsButton("Hide") { shownKey = nil }
                        }
                    } else {
                        OpsButton("Show key card") { Task { shownKey = await model.revealSecretKey() } }
                    }
                }

                Panel(title: "This device") {
                    HStack(alignment: .bottom, spacing: Tok.s1) {
                        OpsField("Device name", text: $deviceName).frame(maxWidth: 320)
                        RowButton("Rename", disabled: deviceName.trimmingCharacters(in: .whitespaces).isEmpty) { model.deviceName = deviceName.trimmingCharacters(in: .whitespaces) }
                    }
                    Rule(quiet: true)
                    Text("Wipe removes the vault file and keys from this device only. Other devices and exported files are not affected.")
                        .font(Type.body()).foregroundStyle(Tok.text2)
                    HStack(spacing: Tok.s1) {
                        if wipeArmed {
                            OpsButton("Confirm wipe", kind: .danger) { model.wipeThisDevice() }
                            OpsButton("Keep") { wipeArmed = false }
                        } else {
                            OpsButton("Wipe this device", kind: .danger) { wipeArmed = true }
                        }
                    }
                }
            }
        }
        .onAppear { deviceName = model.deviceName }
    }
}

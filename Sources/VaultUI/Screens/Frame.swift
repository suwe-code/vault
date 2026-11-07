import SwiftUI
import VaultCore

/// Entry point for both apps.
public struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var covered = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ZStack {
            Tok.bg.ignoresSafeArea()
            switch model.phase {
            case .loading: EmptyView()
            case .welcome: WelcomeScreen(model: model)
            case .setup: SetupScreen(model: model)
            case .adopt: AdoptScreen(model: model)
            case .locked: LockScreen(model: model)
            case .code: CodeScreen(model: model)
            case .unlocked: UnlockedShell(model: model)
            }
            if covered { PrivacyCover() }
        }
        .preferredColorScheme(.dark)
        .font(Type.body())
        .tint(Tok.text)
        .onOpenURL { model.handleIncoming(url: $0) }
        .onChange(of: scenePhase) { _, p in
            #if os(iOS)
            covered = p != .active
            if p == .background, model.phase == .unlocked || model.phase == .code { model.lock() }
            #else
            if p == .background, model.phase == .unlocked { model.lock() }
            #endif
        }
        .onTapGesture { model.touchActivity() }
    }
}

/// Shown over everything while the app is in the switcher. Reveals nothing.
struct PrivacyCover: View {
    var body: some View {
        ZStack { Tok.bg.ignoresSafeArea(); Sig(["VAULT"]) }
    }
}

/// Section 13: place and person above, container, module icons and sync below.
struct Frame<Content: View>: View {
    @ObservedObject var model: AppModel
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Tag("VAULT / \(model.deviceName)")
                Spacer()
                Tag(model.phase == .unlocked ? "\(model.items.count) CARDS" : "LOCKED")
            }
            .padding(.vertical, Tok.s3)
            .frame(maxWidth: Tok.appColumn)

            content()
                .frame(maxWidth: Tok.appColumn, maxHeight: .infinity, alignment: .top)
                .background(Tok.surface.opacity(Type.isPhone ? 0 : 1))
                .overlay(Rectangle().stroke(Type.isPhone ? .clear : Tok.border, lineWidth: 1))

            HStack(alignment: .top) {
                Text(Type.isPhone ? " " : footLeft).font(Type.tag()).foregroundStyle(Tok.text3).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Type.isPhone ? Tok.s3 : Tok.s6) {
                    moduleButton(.cards, "CARDS", .cards)
                    moduleButton(.sync, "SYNC", .sync)
                    moduleButton(.settings, "SETTINGS", .settings)
                }
                Text(Type.isPhone ? " " : footRight).font(Type.tag()).foregroundStyle(Tok.text3).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, Tok.s3)
            .frame(maxWidth: Tok.appColumn)
        }
        .padding(.horizontal, Type.isPhone ? Tok.phoneGutter : Tok.s5)
        .padding(.vertical, Type.isPhone ? Tok.s2 : Tok.s4)
    }

    private var footLeft: String {
        let n = model.items.count
        return n == 0 ? "No cards yet" : "\(n) card\(n == 1 ? "" : "s")"
    }
    private var footRight: String {
        if let d = model.lastSavedAt { return "Saved \(Fmt.stamp(d))" }
        return ""
    }

    private func moduleButton(_ m: Module, _ label: String, _ icon: ModuleIcon) -> some View {
        let on = model.module == m
        return Button { model.module = m; model.selectedItemID = nil; model.editingItem = nil; model.touchActivity() } label: {
            VStack(spacing: Tok.s1) {
                IconView(icon, active: on, size: 22)
                Text(on ? label : " ").font(Type.buttonLabel()).kerning(0.5).foregroundStyle(Tok.text)
            }
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A centred narrow column for gates and wizards, signature at the foot.
struct Gate<Content: View>: View {
    var width: CGFloat = 320
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Tok.s12)
            content().frame(maxWidth: width)
            Spacer(minLength: Tok.s12)
            HStack { Sig(["SUWE", "VAULT"]); Spacer() }.frame(maxWidth: width)
        }
        .padding(.horizontal, Type.isPhone ? Tok.phoneGutter : Tok.s5)
        .padding(.bottom, Tok.s6)
    }
}

// MARK: Lock

struct LockScreen: View {
    @ObservedObject var model: AppModel
    @State private var password = ""
    @State private var typedKey = ""

    var body: some View {
        Gate {
            VStack(alignment: .leading, spacing: Tok.s3) {
                Lbl("Password")
                HStack(spacing: Tok.s1) {
                    OpsField("", text: $password, style: .secure, autofocus: true, onSubmit: submit)
                    RowButton("Unlock", disabled: model.busy || password.isEmpty, action: submit)
                }
                if model.needsTypedKey {
                    OpsField("Secret key", text: $typedKey, style: .mono, placeholder: "VK1-")
                }
                StatusLine(model.status, isError: model.statusIsError)
            }
        }
        .onAppear { password = ""; typedKey = "" }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        if model.needsTypedKey && !typedKey.isEmpty { model.unlock(password: password, typedKey: typedKey) }
        else { model.unlock(password: password) }
    }
}

// MARK: One-time code gate

struct CodeScreen: View {
    @ObservedObject var model: AppModel
    @State private var code = ""

    var body: some View {
        Gate {
            VStack(alignment: .leading, spacing: Tok.s3) {
                Lbl("Code")
                HStack(spacing: Tok.s1) {
                    OpsField("", text: $code, style: .code, autofocus: true, onSubmit: submit)
                    RowButton("Verify", disabled: code.filter(\.isNumber).count != 6, action: submit)
                }
                Text("Authenticator entry VAULT").font(Type.hint()).foregroundStyle(Tok.text3)
                StatusLine(model.status, isError: model.statusIsError)
                OpsButton("Cancel") { model.lock() }
            }
        }
        .onChange(of: code) { _, v in if v.filter(\.isNumber).count == 6 { submit() } }
    }

    private func submit() { model.verifyCode(code); code = "" }
}

// MARK: Welcome

struct WelcomeScreen: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Gate(width: 360) {
            VStack(alignment: .leading, spacing: Tok.s4) {
                Text("No vault on this device").font(Type.title3()).foregroundStyle(Tok.text)
                Text("Create a new vault here, or import the encrypted file exported from another device.")
                    .font(Type.body()).foregroundStyle(Tok.text2)
                HStack(spacing: Tok.s1) {
                    OpsButton("Create vault", kind: .primary) { model.beginSetup() }
                    OpsButton("Import vault file") { model.phase = .adopt }
                }
                StatusLine(model.status, isError: model.statusIsError)
            }
        }
    }
}

// MARK: Unlocked shell

struct UnlockedShell: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Frame(model: model) {
            Group {
                switch model.module {
                case .cards: CardsModule(model: model)
                case .sync: SyncModule(model: model)
                case .settings: SettingsModule(model: model)
                }
            }
            .padding(Type.isPhone ? 0 : Tok.s4)
        }
    }
}

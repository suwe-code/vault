import SwiftUI
import VaultUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct VaultApp: App {
    @StateObject private var model = AppModel()

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

import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import VaultCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Files module: encrypted media on this device. Nothing here is synced; the `.vault` file stays cards only.
///
/// Plain copies exist only while the vault is open:
///   - OPEN and SHARE write a decrypted copy to a private temp folder inside the app container.
///   - DOWNLOAD writes one to the chosen folder (Desktop by default).
/// Both kinds are deleted when the vault locks, the timer quits the app, or the app is quit.
/// A download that is no longer where it was written is reported, then the lock or quit continues.
extension AppModel {

    // MARK: Load / save index

    func loadMedia() {
        guard let v = vault else { media = []; mediaKey = nil; return }
        let key = MediaStore.mediaKey(vaultKey: v.vaultKey)
        mediaKey = key
        do { media = try mediaStore.loadIndex(key: key, vaultID: v.header.vaultID) }
        catch { media = []; setStatus("File index could not be read", error: true) }
    }

    private func saveMediaIndex() {
        guard let key = mediaKey, let id = vaultID else { return }
        do { try mediaStore.saveIndex(media, key: key, vaultID: id) }
        catch { setStatus("File index could not be saved", error: true) }
    }

    public var mediaBytes: Int64 { media.reduce(0) { $0 + $1.size } }

    // MARK: Add

    /// Reads each picked file, encrypts it into the store and records it in the index.
    public func addMedia(urls: [URL]) {
        guard let key = mediaKey, !urls.isEmpty else { return }
        busy = true; setStatus(urls.count == 1 ? "Encrypting" : "Encrypting \(urls.count) files")
        Task {
            var added = 0, failed: [String] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let name = url.lastPathComponent
                let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? ""
                do {
                    let data = try Data(contentsOf: url)
                    let store = mediaStore
                    let entry = try await Task.detached(priority: .userInitiated) { () -> MediaEntry in
                        let thumb = Thumb.make(data, typeID: type)
                        return try store.add(data: data, name: name, type: type, thumbnail: thumb, key: key)
                    }.value
                    media.insert(entry, at: 0)
                    added += 1
                } catch { failed.append(name) }
            }
            saveMediaIndex()
            if failed.isEmpty { setStatus("Added \(added) file\(added == 1 ? "" : "s")") }
            else { setStatus("Could not add \(failed.joined(separator: ", "))", error: true) }
            busy = false
            touchActivity()
        }
    }

    public func deleteMedia(_ id: UUID) {
        guard let i = media.firstIndex(where: { $0.id == id }) else { return }
        let entry = media.remove(at: i)
        mediaStore.remove(entry)
        saveMediaIndex()
        setStatus("Deleted \(entry.name)")
        touchActivity()
    }

    // MARK: Decrypt to a temp copy (open / share)

    private var openDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("open", isDirectory: true) }

    /// Writes a plain copy under a random folder so two files with the same name never collide.
    private func temporaryCopy(_ entry: MediaEntry) throws -> URL {
        guard let key = mediaKey else { throw VaultError.notEnrolled }
        let data = try mediaStore.read(entry, key: key)
        let dir = openDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(entry.name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Opens the file in its default app. The plain copy is removed at lock.
    public func openMedia(_ entry: MediaEntry) {
        do {
            let url = try temporaryCopy(entry)
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
            setStatus("Opened \(entry.name). The copy is removed at lock")
        } catch { setStatus(error.localizedDescription, error: true) }
        touchActivity()
    }

    /// Share sheet with a plain copy, or with a password-protected wrapper when `password` is set.
    /// Both copies are removed at lock.
    public func shareMedia(_ entry: MediaEntry, password: String? = nil) {
        do {
            var url = try temporaryCopy(entry)
            if let pw = password, !pw.isEmpty {
                url = try Protect.wrap(url, typeID: entry.type, password: pw)
                setStatus("Protected as \(url.lastPathComponent). Send the password separately")
            }
            Share.present(url) { [weak self] note in self?.setStatus(note) }
        } catch { setStatus(error.localizedDescription, error: true) }
        touchActivity()
    }

    private func scrubTemporaryCopies() {
        try? FileManager.default.removeItem(at: openDirectory)
    }

    // MARK: Download folder (Desktop by default)

    #if canImport(AppKit)
    /// Sandboxed apps can only write where the user pointed once. The choice is kept as a
    /// security-scoped bookmark, so the folder is asked for a single time.
    private var downloadFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.downloadBookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) { UserDefaults.standard.set(fresh, forKey: Self.downloadBookmarkKey) }
        return url
    }

    public var downloadFolderName: String { downloadFolder?.path(percentEncoded: false) ?? "Not chosen" }

    /// Asks for the folder. Opens on the Desktop.
    @discardableResult
    public func chooseDownloadFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = "Downloads go here and are deleted when the vault locks. Desktop is suggested."
        panel.prompt = "Use this folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let data = try? url.bookmarkData(options: [.withSecurityScope]) {
            UserDefaults.standard.set(data, forKey: Self.downloadBookmarkKey)
            objectWillChange.send()
        }
        return url
    }

    /// Decrypts to the download folder and remembers the path so it can be removed at lock.
    public func downloadMedia(_ entry: MediaEntry) {
        guard let key = mediaKey else { return }
        guard let folder = downloadFolder ?? chooseDownloadFolder() else { return }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        do {
            let data = try mediaStore.read(entry, key: key)
            let url = Self.uniqueURL(in: folder, name: entry.name)
            try data.write(to: url, options: [.atomic])
            var list = trackedDownloads; list.append(url.lastPathComponent); trackedDownloads = list
            setStatus("Downloaded to \(folder.lastPathComponent). Deleted at lock")
        } catch { setStatus("Could not write to \(folder.lastPathComponent)", error: true) }
        touchActivity()
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"); n += 1
        }
        return url
    }

    private var trackedDownloads: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.downloadListKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.downloadListKey) }
    }

    /// Removes every download written since the last lock. Returns the names that were already gone.
    private func removeDownloads() -> [String] {
        let names = trackedDownloads
        guard !names.isEmpty else { return [] }
        trackedDownloads = []
        guard let folder = downloadFolder else { return names }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        var missing: [String] = []
        for n in names {
            let url = folder.appendingPathComponent(n)
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
            else { missing.append(n) }
        }
        return missing
    }
    #else
    private func removeDownloads() -> [String] { [] }
    #endif

    static let downloadBookmarkKey = "downloadFolderBookmark"
    static let downloadListKey = "downloadedFiles"

    // MARK: Lock / quit hooks

    /// Clears plain copies. Called from every lock path and at launch (for copies left by a crash).
    public func cleanPlainCopies() -> [String] {
        scrubTemporaryCopies()
        return removeDownloads()
    }

    /// Called at launch: anything left from a previous run is removed quietly.
    func sweepLeftovers() { _ = cleanPlainCopies() }

    public static func missingMessage(_ names: [String]) -> String {
        "Already gone from the download folder, so it could not be deleted:\n" + names.map { "• \($0)" }.joined(separator: "\n")
    }
}

// MARK: Thumbnails

enum Thumb {
    static let side: CGFloat = 320

    /// Small JPEG for image files. Everything else gets no preview.
    static func make(_ data: Data, typeID: String) -> Data? {
        guard let t = UTType(typeID), t.conforms(to: .image) else { return nil }
        #if canImport(AppKit)
        guard let img = NSImage(data: data), img.size.width > 0 else { return nil }
        let scale = min(1, side / max(img.size.width, img.size.height))
        let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let out = NSImage(size: size)
        out.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        #else
        guard let img = UIImage(data: data), img.size.width > 0 else { return nil }
        let scale = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let r = UIGraphicsImageRenderer(size: size)
        return r.jpegData(withCompressionQuality: 0.7) { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        #endif
    }
}

// MARK: Share sheet

/// System share sheet. Telegram appears through its share extension (enabled in
/// System Settings › General › Login Items & Extensions › Sharing). WhatsApp's Mac app has
/// no share extension, so a WhatsApp entry is added that copies the file and opens WhatsApp;
/// paste into the chat with Cmd-V.
enum Share {
    #if canImport(AppKit)
    private final class Extra: NSObject, NSSharingServicePickerDelegate {
        let note: (String) -> Void
        init(note: @escaping (String) -> Void) { self.note = note }
        func sharingServicePicker(_ picker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
            var list = proposed
            let wa = "/Applications/WhatsApp.app"
            if FileManager.default.fileExists(atPath: wa), let url = items.first as? URL {
                let icon = NSWorkspace.shared.icon(forFile: wa)
                let svc = NSSharingService(title: "WhatsApp", image: icon, alternateImage: icon) { [note] in
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([url as NSURL])
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: wa), configuration: NSWorkspace.OpenConfiguration())
                    note("File copied. Paste it into the WhatsApp chat with Cmd-V")
                }
                list.insert(svc, at: 0)
            }
            return list
        }
    }
    private static var extra: Extra?
    #endif

    static func present(_ url: URL, note: @escaping (String) -> Void) {
        #if canImport(AppKit)
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let p = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let picker = NSSharingServicePicker(items: [url])
        let d = Extra(note: note); extra = d
        picker.delegate = d
        picker.show(relativeTo: NSRect(x: p.x, y: p.y, width: 1, height: 1), of: view, preferredEdge: .minY)
        #else
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(vc, animated: true)
        #endif
    }
}

// MARK: Formatting

extension Fmt {
    public static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: n)
    }
}

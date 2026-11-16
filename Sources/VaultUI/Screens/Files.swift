import SwiftUI
import UniformTypeIdentifiers
import VaultCore

/// FILES module: encrypted media kept on this device. Same grid of equal rectangles as CARDS,
/// same tile size. Drop files anywhere on the page or use Add files. Each tile has a row of
/// icon actions: open, share, download, delete. Nothing leaves the store unencrypted except
/// the plain copies those actions make, which are removed at lock.
struct FilesModule: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var picking = false
    @State private var kind: FileKind? = nil
    @State private var dropping = false

    enum FileKind: Hashable, CaseIterable {
        case image, video, document, other
        var label: String {
            switch self { case .image: "IMAGES"; case .video: "VIDEO"; case .document: "DOCS"; case .other: "OTHER" }
        }
        static func of(_ e: MediaEntry) -> FileKind {
            guard let t = UTType(e.type) else { return .other }
            if t.conforms(to: .image) { return .image }
            if t.conforms(to: .movie) || t.conforms(to: .audio) { return .video }
            if t.conforms(to: .pdf) || t.conforms(to: .text) || t.conforms(to: .spreadsheet) || t.conforms(to: .presentation) || t.conforms(to: .archive) { return .document }
            return .other
        }
    }

    private var counts: [(FileKind?, String)] {
        var out: [(FileKind?, String)] = [(nil, "ALL \(model.media.count)")]
        for k in FileKind.allCases {
            let n = model.media.filter { FileKind.of($0) == k }.count
            if n > 0 { out.append((k, "\(k.label) \(n)")) }
        }
        return out
    }

    private var visible: [MediaEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.media
            .filter { kind == nil || FileKind.of($0) == kind }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            if Type.isPhone {
                VStack(alignment: .leading, spacing: Tok.s2) {
                    ScrollView(.horizontal, showsIndicators: false) { Segmented(counts, selection: $kind) }
                    HStack(spacing: Tok.s1) {
                        OpsField("", text: $query, placeholder: "Search")
                        RowButton("Add files", kind: .primary, disabled: model.busy) { picking = true }
                    }
                }
            } else {
                HStack(spacing: Tok.s3) {
                    Segmented(counts, selection: $kind)
                    OpsField("", text: $query, placeholder: "Search").frame(maxWidth: 220)
                    Spacer()
                    OpsButton("Add files", kind: .primary, disabled: model.busy) { picking = true }
                }
            }
            if model.media.isEmpty {
                VStack(alignment: .leading, spacing: Tok.s2) {
                    Text(Type.isPhone ? "No files yet" : "No files yet. Drop files here or use Add files.").font(Type.meta()).foregroundStyle(Tok.text3)
                    Text("Files added here are encrypted on this device and never leave it through sync. Remove the originals yourself.")
                        .font(Type.hint()).foregroundStyle(Tok.text3)
                }
                .padding(.top, Tok.s6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if visible.isEmpty {
                Text("No match").font(Type.meta()).foregroundStyle(Tok.text3).padding(.top, Tok.s6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { geo in
                    let gap = Tok.s3
                    let n = Type.isPhone ? 1 : max(1, Int((geo.size.width + gap) / (Tok.cardMin + gap)))
                    let side = (geo.size.width - CGFloat(n - 1) * gap) / CGFloat(n)
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: n), alignment: .leading, spacing: gap) {
                            ForEach(visible) { e in
                                FileTile(model: model, entry: e).frame(width: side, height: Tok.cardHeight)
                            }
                        }
                        .padding(.bottom, Tok.s4)
                    }
                }
            }
            StatusLine(model.status, isError: model.statusIsError)
        }
        .overlay(Rectangle().stroke(dropping ? Tok.text : .clear, lineWidth: 1).padding(-Tok.s2))
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            Drop.urls(from: providers) { urls in model.addMedia(urls: urls) }
            return true
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { model.addMedia(urls: urls) }
        }
    }
}

/// Finder drops arrive as file URL data on item providers; they are resolved off the main thread.
enum Drop {
    static func urls(from providers: [NSItemProvider], done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var out: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { lock.lock(); out.append(url); lock.unlock() }
            }
        }
        group.notify(queue: .main) { done(out) }
    }
}

// MARK: Tile

struct FileTile: View {
    @ObservedObject var model: AppModel
    let entry: MediaEntry
    @State private var hover = false
    @State private var confirmDelete = false
    @State private var sharing = false
    @State private var sharePassword = ""

    private var typeLabel: String {
        let ext = entry.fileExtension
        if !ext.isEmpty { return ext }
        return UTType(entry.type)?.preferredFilenameExtension ?? "file"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: Tok.cardHeight - 86)
                .clipped()
                .background(Tok.recessed)
                .overlay(Rectangle().stroke(Tok.divider, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { if !Type.isPhone { model.openMedia(entry) } }
            VStack(alignment: .leading, spacing: Tok.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Tok.s2) {
                    Text(entry.name).font(Type.bodyStrong()).foregroundStyle(Tok.text).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Tok.s2)
                    Tag(typeLabel)
                }
                HStack(spacing: Tok.s2) {
                    Text("\(Fmt.bytes(entry.size))  \(Fmt.day(entry.addedAt))").font(Type.tag()).foregroundStyle(Tok.text3).lineLimit(1)
                    Spacer(minLength: Tok.s2)
                    actions
                }
            }
            .padding(.top, Tok.s2)
        }
        .padding(Tok.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.surface)
        .overlay(Rectangle().stroke(hover ? Tok.text3 : Tok.border, lineWidth: 1))
        .onHover { hover = $0; if !$0 { confirmDelete = false } }
    }

    @ViewBuilder private var preview: some View {
        if let data = entry.thumbnail, let img = PlatformImage.from(data) {
            img.resizable().aspectRatio(contentMode: .fill)
        } else {
            Text(typeLabel.uppercased()).font(Type.dataLg()).foregroundStyle(Tok.text3)
        }
    }

    /// Icon row, always visible. Dim at rest, full when the tile is hovered.
    private var actions: some View {
        HStack(spacing: Tok.s1) {
            if !Type.isPhone {
                IconButton("arrow.up.right.square", help: "Open", dim: !hover) { model.openMedia(entry) }
            }
            IconButton("square.and.arrow.up", help: "Share", dim: !hover) { sharing = true }
                .popover(isPresented: $sharing, arrowEdge: .bottom) { sharePopover }
            #if os(macOS)
            IconButton("arrow.down.to.line", help: "Download to folder", dim: !hover) { model.downloadMedia(entry) }
            #endif
            if confirmDelete {
                Button { model.deleteMedia(entry.id) } label: { Lbl("Confirm", color: Tok.err).padding(.horizontal, Tok.s1) }.buttonStyle(.plain)
            } else {
                IconButton("trash", help: "Delete", dim: !hover) { confirmDelete = true }
            }
        }
    }

    /// Share as is, or set a password the recipient will need.
    private var sharePopover: some View {
        VStack(alignment: .leading, spacing: Tok.s3) {
            Text(entry.name).font(Type.bodyStrong()).foregroundStyle(Tok.text).lineLimit(1).truncationMode(.middle)
            OpsButton("Share as is", kind: .primary) { share(nil) }
            Rule(quiet: true)
            Lbl("Or protect with a password")
            OpsField("", text: $sharePassword, style: .secure, placeholder: "Password for the recipient", onSubmit: { share(sharePassword) })
            OpsButton("Share protected", disabled: sharePassword.isEmpty) { share(sharePassword) }
            Text(protectHint).font(Type.hint()).foregroundStyle(Tok.text3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tok.s4)
        .frame(width: 300)
        .background(Tok.surface)
    }

    private var protectHint: String {
        let t = UTType(entry.type)
        if t?.conforms(to: .pdf) == true || t?.conforms(to: .image) == true {
            return "Sent as an encrypted PDF. Opens in any PDF viewer with the password."
        }
        return "Sent as a password-protected ZIP. Mac and Windows open it with The Unarchiver, Keka or 7-Zip; phones need a zip app. Tell the recipient the password by another channel."
    }

    private func share(_ pw: String?) {
        sharing = false
        let password = pw
        sharePassword = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { model.shareMedia(entry, password: password) }
    }
}

/// 14pt symbol in a 24pt square hit area.
struct IconButton: View {
    let symbol: String
    let help: String
    var dim = false
    let action: () -> Void
    @State private var hover = false
    init(_ symbol: String, help: String, dim: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol; self.help = help; self.dim = dim; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Type.isPhone ? 16 : 14, weight: .medium))
                .foregroundStyle(hover ? Tok.text : (dim ? Tok.text3 : Tok.text2))
                .frame(width: Type.isPhone ? 32 : 24, height: Type.isPhone ? 32 : 24)
                .background(hover ? Tok.elevated : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

enum PlatformImage {
    static func from(_ data: Data) -> Image? {
        #if canImport(AppKit)
        guard let i = NSImage(data: data) else { return nil }
        return Image(nsImage: i)
        #else
        guard let i = UIImage(data: data) else { return nil }
        return Image(uiImage: i)
        #endif
    }
}

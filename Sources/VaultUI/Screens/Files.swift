import SwiftUI
import UniformTypeIdentifiers
import VaultCore

/// FILES module: encrypted media kept on this device. Same grid of equal rectangles as CARDS.
/// Hover a tile for OPEN / SHARE / DOWNLOAD / DELETE. Nothing leaves the store unencrypted
/// except the plain copies those actions make, which are removed at lock.
struct FilesModule: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var picking = false
    @State private var kind: FileKind? = nil

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
                    Text("No files yet").font(Type.meta()).foregroundStyle(Tok.text3)
                    Text("Files added here are encrypted on this device and never leave it through sync. Remove the originals yourself.")
                        .font(Type.hint()).foregroundStyle(Tok.text3)
                }
                .padding(.top, Tok.s6)
            } else if visible.isEmpty {
                Text("No match").font(Type.meta()).foregroundStyle(Tok.text3).padding(.top, Tok.s6)
            } else {
                GeometryReader { geo in
                    let gap = Tok.s3
                    let n = Type.isPhone ? 2 : max(1, Int((geo.size.width + gap) / (Tok.fileMin + gap)))
                    let side = (geo.size.width - CGFloat(n - 1) * gap) / CGFloat(n)
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: n), alignment: .leading, spacing: gap) {
                            ForEach(visible) { e in
                                FileTile(model: model, entry: e).frame(width: side, height: Tok.fileHeight)
                            }
                        }
                        .padding(.bottom, Tok.s4)
                    }
                }
            }
            StatusLine(model.status, isError: model.statusIsError)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { model.addMedia(urls: urls) }
        }
    }
}

// MARK: Tile

struct FileTile: View {
    @ObservedObject var model: AppModel
    let entry: MediaEntry
    @State private var hover = false
    @State private var confirmDelete = false

    private var showActions: Bool { Type.isPhone || hover }
    private var typeLabel: String {
        let ext = entry.fileExtension
        if !ext.isEmpty { return ext }
        return UTType(entry.type)?.preferredFilenameExtension ?? "file"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: Tok.fileHeight - 74)
                .clipped()
                .background(Tok.recessed)
                .overlay(Rectangle().stroke(Tok.divider, lineWidth: 1))
            VStack(alignment: .leading, spacing: Tok.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Tok.s2) {
                    Text(entry.name).font(Type.bodyStrong()).foregroundStyle(Tok.text).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Tok.s2)
                    Tag(typeLabel)
                }
                HStack(spacing: Tok.s2) {
                    Text("\(Fmt.bytes(entry.size))  \(Fmt.day(entry.addedAt))").font(Type.tag()).foregroundStyle(Tok.text3).lineLimit(1)
                    Spacer(minLength: Tok.s2)
                    if showActions { actions }
                }
            }
            .padding(.top, Tok.s2)
        }
        .padding(Tok.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.surface)
        .overlay(Rectangle().stroke(hover ? Tok.text3 : Tok.border, lineWidth: 1))
        .onHover { hover = $0; if !$0 { confirmDelete = false } }
        .onTapGesture { if !Type.isPhone { model.openMedia(entry) } }
    }

    @ViewBuilder private var preview: some View {
        if let data = entry.thumbnail, let img = PlatformImage.from(data) {
            img.resizable().aspectRatio(contentMode: .fill)
        } else {
            Text(typeLabel.uppercased()).font(Type.dataLg()).foregroundStyle(Tok.text3)
        }
    }

    private var actions: some View {
        HStack(spacing: Tok.s2) {
            if !Type.isPhone {
                Button { model.openMedia(entry) } label: { Lbl("Open", color: Tok.text2) }.buttonStyle(.plain)
            }
            Button { model.shareMedia(entry) } label: { Lbl("Share", color: Tok.text2) }.buttonStyle(.plain)
            #if os(macOS)
            Button { model.downloadMedia(entry) } label: { Lbl("Download", color: Tok.text2) }.buttonStyle(.plain)
            #endif
            if confirmDelete {
                Button { model.deleteMedia(entry.id) } label: { Lbl("Confirm", color: Tok.err) }.buttonStyle(.plain)
            } else {
                Button { confirmDelete = true } label: { Lbl("Delete", color: Tok.text2) }.buttonStyle(.plain)
            }
        }
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

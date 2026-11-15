import SwiftUI
import VaultCore

struct CardsModule: View {
    @ObservedObject var model: AppModel
    @State private var filter: ItemCategory? = nil
    @State private var query = ""

    var body: some View {
        if let draft = model.editingItem {
            CardEditor(model: model, original: draft, isNew: model.item(draft.id) == nil) { model.editingItem = nil }
        } else if let item = model.item(model.selectedItemID) {
            CardDetail(model: model, item: item, onEdit: { model.editingItem = item })
        } else {
            list
        }
    }

    private var counts: [(ItemCategory?, String)] {
        var out: [(ItemCategory?, String)] = [(nil, "ALL \(model.items.count)")]
        for c in ItemCategory.allCases {
            let n = model.items.filter { $0.category == c }.count
            if n > 0 { out.append((c, "\(c.label) \(n)")) }
        }
        return out
    }

    private var visible: [VaultItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.items
            .filter { filter == nil || $0.category == filter }
            .filter { q.isEmpty || $0.searchText.contains(q) }
            .sorted { a, b in
                if a.favourite != b.favourite { return a.favourite }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            if Type.isPhone {
                VStack(alignment: .leading, spacing: Tok.s2) {
                    ScrollView(.horizontal, showsIndicators: false) { Segmented(counts, selection: $filter) }
                    HStack(spacing: Tok.s1) {
                        OpsField("", text: $query, placeholder: "Search")
                        RowButton("Add", kind: .primary) { newCard() }
                    }
                }
            } else {
                HStack(spacing: Tok.s3) {
                    Segmented(counts, selection: $filter)
                    OpsField("", text: $query, placeholder: "Search title, label or tag").frame(maxWidth: 280)
                    Spacer()
                    OpsButton("Add card", kind: .primary) { newCard() }
                }
            }
            if model.items.isEmpty {
                Text("No cards yet").font(Type.meta()).foregroundStyle(Tok.text3).padding(.top, Tok.s6)
            } else if visible.isEmpty {
                Text("No match").font(Type.meta()).foregroundStyle(Tok.text3).padding(.top, Tok.s6)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if !Type.isPhone {
                            HStack(spacing: Tok.s3) {
                                Lbl("Title").frame(maxWidth: .infinity, alignment: .leading)
                                Lbl("Type").frame(width: 90, alignment: .leading)
                                Lbl("Fields").frame(width: 60, alignment: .trailing)
                                Lbl("Updated").frame(width: 120, alignment: .trailing)
                            }
                            .padding(.vertical, Tok.s25)
                            Rule()
                        }
                        ForEach(visible) { item in
                            CardRow(item: item) { model.selectedItemID = item.id; model.touchActivity() }
                            Rule(quiet: true)
                        }
                    }
                }
            }
        }
    }

    private func newCard() {
        model.editingItem = VaultItem(title: "", category: .login, fields: Templates.fields(for: .login))
    }
}

struct CardRow: View {
    let item: VaultItem
    let open: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: open) {
            if Type.isPhone {
                HStack(spacing: Tok.s3) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(Type.bodyStrong()).foregroundStyle(Tok.text).lineLimit(1)
                        Tag(item.category.label)
                    }
                    Spacer()
                    Text(Fmt.day(item.modifiedAt)).font(Type.tag()).foregroundStyle(Tok.text3)
                }
                .padding(.vertical, Tok.s3)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: Tok.s3) {
                    HStack(spacing: Tok.s2) {
                        if item.favourite { Rectangle().fill(Tok.text).frame(width: 6, height: 6) }
                        Text(item.title).font(Type.bodyStrong()).foregroundStyle(Tok.text).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Tag(item.category.label).frame(width: 90, alignment: .leading)
                    Text("\(item.fields.filter { !$0.value.isEmpty }.count)").font(Type.dataBody()).foregroundStyle(Tok.text2).frame(width: 60, alignment: .trailing)
                    Text(Fmt.stamp(item.modifiedAt)).font(Type.dataBody()).foregroundStyle(Tok.text2).frame(width: 120, alignment: .trailing)
                }
                .padding(.vertical, Tok.s25)
                .background(hover ? Tok.elevated : .clear)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Detail

/// Design section 07 "Card": bordered panel on surface, 16px padding, title-3 header with a tag at the
/// right, label left and mono value right. Hovering a row shows its actions; clicking a value copies it.
struct CardDetail: View {
    @ObservedObject var model: AppModel
    let item: VaultItem
    let onEdit: () -> Void
    @State private var revealed: Set<UUID> = []
    @State private var confirmDelete = false

    private var filled: [VaultField] { item.fields.filter { !$0.value.isEmpty } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tok.s4) {
                HStack(spacing: Tok.s1) {
                    OpsButton("Back") { model.selectedItemID = nil }
                    Spacer()
                    OpsButton("Edit", action: onEdit)
                    if confirmDelete {
                        OpsButton("Confirm delete", kind: .danger) { model.delete(item.id) }
                        OpsButton("Keep") { confirmDelete = false }
                    } else {
                        OpsButton("Delete", kind: .danger) { confirmDelete = true }
                    }
                }
                card
                HStack {
                    Text("Created \(Fmt.stamp(item.createdAt))   Updated \(Fmt.stamp(item.modifiedAt))").font(Type.hint()).foregroundStyle(Tok.text3)
                    Spacer()
                    StatusLine(model.status, isError: model.statusIsError)
                }
                .frame(maxWidth: cardWidth)
            }
        }
    }

    private var cardWidth: CGFloat { Type.isPhone ? .infinity : 560 }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Tok.s3) {
                Text(item.title).font(Type.title3()).foregroundStyle(Tok.text).lineLimit(2)
                Spacer()
                HStack(spacing: Tok.s2) {
                    if item.favourite { Rectangle().fill(Tok.text).frame(width: 6, height: 6) }
                    Tag(item.category.label)
                }
            }
            .padding(.bottom, Tok.s3)
            if filled.isEmpty && item.notes.isEmpty {
                Text("Nothing entered yet").font(Type.meta()).foregroundStyle(Tok.text3).padding(.vertical, Tok.s3)
            }
            ForEach(filled) { f in
                CardFieldRow(field: f, revealed: revealed.contains(f.id),
                             toggle: { if revealed.contains(f.id) { revealed.remove(f.id) } else { revealed.insert(f.id) }; model.touchActivity() },
                             copy: { text, secret in model.copy(text, secret: secret) })
                Rule(quiet: true)
            }
            if !item.notes.isEmpty {
                VStack(alignment: .leading, spacing: Tok.s2) {
                    Lbl("Notes")
                    Text(item.notes).font(Type.body()).foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Tok.s3)
            }
            if !item.tags.isEmpty {
                HStack(spacing: Tok.s3) { ForEach(item.tags, id: \.self) { Tag($0) } }
                    .padding(.top, Tok.s3)
            }
        }
        .padding(Tok.s4)
        .frame(maxWidth: cardWidth, alignment: .leading)
        .background(Tok.surface)
        .overlay(Rectangle().stroke(Tok.border, lineWidth: 1))
    }
}

/// One card row. Label left in caps, value right in mono. Hover highlights the row and shows
/// REVEAL / COPY at the end; clicking anywhere on the row copies the value. Phones show the actions always.
struct CardFieldRow: View {
    let field: VaultField
    let revealed: Bool
    let toggle: () -> Void
    let copy: (String, Bool) -> Void
    @State private var hover = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isOTP: Bool { field.kind == .otpSecret }
    private var showActions: Bool { Type.isPhone || hover }

    var body: some View {
        Group {
            if Type.isPhone {
                // Field layout: label above, value and actions below.
                VStack(alignment: .leading, spacing: Tok.s2) {
                    Lbl(field.label)
                    HStack(alignment: .firstTextBaseline, spacing: Tok.s3) {
                        value.multilineTextAlignment(.leading)
                        Spacer(minLength: Tok.s2)
                        actions
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Tok.s3) {
                    Lbl(field.label).frame(width: 150, alignment: .leading)
                    Spacer(minLength: Tok.s2)
                    value
                    if showActions { actions.frame(width: actionsWidth, alignment: .trailing) }
                    else { Color.clear.frame(width: actionsWidth, height: 1) }
                }
            }
        }
        .padding(.vertical, Tok.s25)
        .padding(.horizontal, Tok.s2)
        .background(hover ? Tok.elevated : .clear)
        .contentShape(Rectangle())
        .onTapGesture { doCopy() }
        .onHover { hover = $0 }
        .onReceive(timer) { tick = $0 }
    }

    private var actionsWidth: CGFloat { field.kind.isSecret && !isOTP ? 86 : 40 }

    private var actions: some View {
        HStack(spacing: Tok.s3) {
            if field.kind.isSecret && !isOTP {
                Button(action: toggle) { Lbl(revealed ? "Hide" : "Reveal", color: Tok.text2) }.buttonStyle(.plain)
            }
            Button(action: doCopy) { Lbl("Copy", color: Tok.text2) }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var value: some View {
        if isOTP {
            if let seed = Base32.decode(field.value), !seed.isEmpty {
                let t = TOTP(secret: seed)
                HStack(spacing: Tok.s2) {
                    Text(t.code(at: tick)).font(Type.data()).foregroundStyle(Tok.text)
                    Text("\(t.secondsRemaining(at: tick)) s").font(Type.tag()).foregroundStyle(Tok.text3)
                }
            } else {
                Text("Invalid seed").font(Type.meta()).foregroundStyle(Tok.err)
            }
        } else if field.kind.isSecret && !revealed {
            Text(String(repeating: "•", count: min(field.value.count, 14))).font(Type.data()).foregroundStyle(Tok.text2)
        } else {
            Text(field.value).font(field.kind.isMono ? Type.data() : Type.body()).foregroundStyle(Tok.text)
                .multilineTextAlignment(.trailing).lineLimit(4)
        }
    }

    private func doCopy() {
        if isOTP, let seed = Base32.decode(field.value) { copy(TOTP(secret: seed).code(), true) }
        else { copy(field.value, field.kind.isSecret) }
    }
}

// MARK: Editor

struct CardEditor: View {
    @ObservedObject var model: AppModel
    @State var draft: VaultItem
    let isNew: Bool
    let done: () -> Void
    @State private var tagsText: String

    init(model: AppModel, original: VaultItem, isNew: Bool, done: @escaping () -> Void) {
        self.model = model; self._draft = State(initialValue: original); self.isNew = isNew; self.done = done
        self._tagsText = State(initialValue: original.tags.joined(separator: ", "))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tok.s4) {
                HStack(spacing: Tok.s3) {
                    Text(isNew ? "New card" : "Edit card").font(Type.title3()).foregroundStyle(Tok.text)
                    Spacer()
                    if !Type.isPhone { actions }
                }
                VStack(alignment: .leading, spacing: Tok.s2) {
                    Lbl("Type")
                    ScrollView(.horizontal, showsIndicators: false) {
                        Segmented(ItemCategory.allCases.map { ($0, $0.label) }, selection: $draft.category)
                    }
                    if isNew {
                        Text("Starter fields for the type. Empty ones are dropped on save. Remove or add any field.").font(Type.hint()).foregroundStyle(Tok.text3)
                    }
                }
                .onChange(of: draft.category) { _, c in
                    if isNew && draft.fields.allSatisfy({ $0.value.isEmpty }) { draft.fields = Templates.fields(for: c) }
                }
                OpsField("Title", text: $draft.title, placeholder: "", autofocus: isNew)
                VStack(alignment: .leading, spacing: Tok.s2) {
                    Lbl("Fields")
                    VStack(spacing: Tok.s2) {
                        ForEach($draft.fields) { $f in
                            FieldEditRow(field: $f) { draft.fields.removeAll { $0.id == f.id } }
                        }
                    }
                    OpsButton("Add field") { draft.fields.append(VaultField(label: "", value: "", kind: .text)) }
                }
                OpsTextArea("Notes", text: $draft.notes)
                OpsField("Tags", text: $tagsText, hint: "Comma separated")
                HStack {
                    Toggle(isOn: $draft.favourite) { Lbl("Pin to top", color: Tok.text2) }.toggleStyle(.checkbox).tint(Tok.text)
                    Spacer()
                    StatusLine(model.status, isError: model.statusIsError).frame(maxWidth: 240)
                }
                if Type.isPhone { actions }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Tok.s1) {
            OpsButton("Save", kind: .primary, disabled: draft.title.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
            OpsButton("Cancel") { done() }
        }
    }

    private func save() {
        var it = draft
        it.title = it.title.trimmingCharacters(in: .whitespaces)
        it.fields = it.fields.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        it.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        model.upsert(it)
        model.selectedItemID = it.id
        done()
    }
}

struct FieldEditRow: View {
    @Binding var field: VaultField
    let remove: () -> Void
    var body: some View {
        if Type.isPhone {
            VStack(spacing: Tok.s1) {
                HStack(spacing: Tok.s1) {
                    OpsField("", text: $field.label, placeholder: "Label")
                    kindButton
                    RowButton("Remove", action: remove)
                }
                OpsField("", text: $field.value, style: field.kind.isMono ? .mono : .text, placeholder: field.kind.label.capitalized)
            }
        } else {
            HStack(spacing: Tok.s1) {
                OpsField("", text: $field.label, placeholder: "Label").frame(width: 180)
                OpsField("", text: $field.value, style: field.kind.isMono ? .mono : .text, placeholder: field.kind.label.capitalized)
                kindButton
                RowButton("Remove", action: remove)
            }
        }
    }
    /// Tapping cycles the field kind. Terse, no menus.
    private var kindButton: some View {
        RowButton(field.kind.label) {
            let all = FieldKind.allCases
            let i = all.firstIndex(of: field.kind) ?? 0
            field.kind = all[(i + 1) % all.count]
        }
        .frame(width: 118)
    }
}

#if os(iOS)
extension ToggleStyle where Self == SwitchToggleStyle { static var checkbox: SwitchToggleStyle { .switch } }
#endif

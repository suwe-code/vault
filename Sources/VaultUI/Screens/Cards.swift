import SwiftUI
import VaultCore

struct CardsModule: View {
    @ObservedObject var model: AppModel
    @State private var filter: ItemCategory? = nil
    @State private var query = ""

    var body: some View {
        if let draft = model.editingItem {
            CardEditor(model: model, original: draft, isNew: model.item(draft.id) == nil) { model.editingItem = nil }
        } else {
            grid
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
                // Logins, then bank, then cards, then the rest. Pinned first within a type, then by title.
                let order = ItemCategory.allCases
                let ia = order.firstIndex(of: a.category) ?? 0, ib = order.firstIndex(of: b.category) ?? 0
                if ia != ib { return ia < ib }
                if a.favourite != b.favourite { return a.favourite }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    /// Every card is shown whole, small, in a scrolling grid. Values copy from here; nothing opens.
    private var grid: some View {
        VStack(alignment: .leading, spacing: Tok.s4) {
            if Type.isPhone {
                VStack(alignment: .leading, spacing: Tok.s2) {
                    ScrollView(.horizontal, showsIndicators: false) { Segmented(counts, selection: $filter) }
                    HStack(spacing: Tok.s1) {
                        OpsField("", text: $query, placeholder: "Search")
                        RowButton("Add new", kind: .primary) { newCard() }
                    }
                }
            } else {
                HStack(spacing: Tok.s3) {
                    Segmented(counts, selection: $filter)
                    OpsField("", text: $query, placeholder: "Search").frame(maxWidth: 220)
                    Spacer()
                    OpsButton("Add new credentials", kind: .primary) { newCard() }
                }
            }
            if model.items.isEmpty {
                Text("No cards yet").font(Type.meta()).foregroundStyle(Tok.text3).padding(.top, Tok.s6)
            } else if visible.isEmpty {
                Text("No match").font(Type.meta()).foregroundStyle(Tok.text3).padding(.top, Tok.s6)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Type.isPhone ? 300 : 260, maximum: 340), spacing: Tok.s3, alignment: .top)],
                              alignment: .leading, spacing: Tok.s3) {
                        ForEach(visible) { item in
                            MiniCard(model: model, item: item) { model.editingItem = item }
                        }
                    }
                    .padding(.bottom, Tok.s4)
                }
            }
            StatusLine(model.status, isError: model.statusIsError)
        }
    }

    private func newCard() {
        model.editingItem = VaultItem(title: "", category: .login, fields: Templates.fields(for: .login))
    }
}

// MARK: Mini card

/// Design section 07 "Card", compact: bordered panel on surface, 12px padding, title with the type tag
/// at the right, label left and mono value right. Hover a row for REVEAL / COPY; click the row to copy.
struct MiniCard: View {
    @ObservedObject var model: AppModel
    let item: VaultItem
    let onEdit: () -> Void
    @State private var revealed: Set<UUID> = []
    @State private var hover = false

    private var filled: [VaultField] { item.fields.filter { !$0.value.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Tok.s2) {
                if item.favourite { Rectangle().fill(Tok.text).frame(width: 5, height: 5) }
                Text(item.title).font(Type.bodyStrong()).foregroundStyle(Tok.text).lineLimit(1)
                Spacer(minLength: Tok.s2)
                Tag(item.category.label)
                if hover || Type.isPhone {
                    Button(action: onEdit) { Lbl("Edit", color: Tok.text2) }.buttonStyle(.plain)
                }
            }
            .padding(.bottom, Tok.s2)
            Rule(quiet: true)
            if filled.isEmpty && item.notes.isEmpty {
                Text("Nothing entered").font(Type.hint()).foregroundStyle(Tok.text3).padding(.vertical, Tok.s2)
            }
            ForEach(filled) { f in
                CardFieldRow(field: f, revealed: revealed.contains(f.id),
                             toggle: { if revealed.contains(f.id) { revealed.remove(f.id) } else { revealed.insert(f.id) }; model.touchActivity() },
                             copy: { text, secret in model.copy(text, secret: secret) })
                Rule(quiet: true)
            }
            if !item.notes.isEmpty {
                Text(item.notes).font(Type.hint()).foregroundStyle(Tok.text2).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tok.s2)
            }
        }
        .padding(Tok.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.surface)
        .overlay(Rectangle().stroke(hover ? Tok.text3 : Tok.border, lineWidth: 1))
        .onHover { hover = $0 }
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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Tok.s2) {
                Lbl(field.label).lineLimit(1)
                Spacer(minLength: Tok.s2)
                if showActions { actions }
            }
            HStack(spacing: 0) {
                value
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Tok.s2)
        .padding(.horizontal, Tok.s1)
        .background(hover ? Tok.elevated : .clear)
        .contentShape(Rectangle())
        .onTapGesture { doCopy() }
        .onHover { hover = $0 }
        .onReceive(timer) { tick = $0 }
    }

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
            Text(String(repeating: "•", count: min(field.value.count, 14))).font(Type.dataBody()).foregroundStyle(Tok.text2)
        } else {
            Text(field.value).font(field.kind.isMono ? Type.dataBody() : Type.cell()).foregroundStyle(Tok.text)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
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
                    Text(isNew ? "New credentials" : "Edit credentials").font(Type.title3()).foregroundStyle(Tok.text)
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

    @State private var confirmDelete = false
    private var actions: some View {
        HStack(spacing: Tok.s1) {
            OpsButton("Save", kind: .primary, disabled: draft.title.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
            OpsButton("Cancel") { done() }
            if !isNew {
                if confirmDelete {
                    OpsButton("Confirm delete", kind: .danger) { model.delete(draft.id); done() }
                    OpsButton("Keep") { confirmDelete = false }
                } else {
                    OpsButton("Delete", kind: .danger) { confirmDelete = true }
                }
            }
        }
    }

    private func save() {
        var it = draft
        it.title = it.title.trimmingCharacters(in: .whitespaces)
        it.fields = it.fields.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        it.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        model.upsert(it)
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

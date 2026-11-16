import SwiftUI

// MARK: Labels and text

/// label: Geist 600 10/1 +0.06em CAPS, text-3.
public struct Lbl: View {
    let text: String
    var color: Color = Tok.text3
    public init(_ text: String, color: Color = Tok.text3) { self.text = text; self.color = color }
    public var body: some View {
        Text(text.uppercased()).font(Type.label()).kerning(0.6).foregroundStyle(color).lineLimit(1)
    }
}

/// tag: Mono 500 10/1 CAPS, text-2.
public struct Tag: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased()).font(Type.tag()).foregroundStyle(Tok.text2).lineLimit(1)
    }
}

/// Page signature, mono 10, +0.08em, 50% opacity.
public struct Sig: View {
    let lines: [String]
    public init(_ lines: [String]) { self.lines = lines }
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { Text($0.uppercased()).font(Type.sig()).kerning(0.8) }
        }
        .foregroundStyle(Tok.text3).opacity(0.5)
    }
}

/// 1px hairline. `quiet` uses divider instead of border.
public struct Rule: View {
    var quiet = false
    public init(quiet: Bool = false) { self.quiet = quiet }
    public var body: some View { Rectangle().fill(quiet ? Tok.divider : Tok.border).frame(height: Tok.hairline) }
}

// MARK: Buttons

public enum ButtonKind { case normal, primary, danger }

/// 18px desktop / 44px phone, 1px border, 9px caps label, intrinsic width.
/// Transparent by default. Primary is the only filled control on a screen.
public struct OpsButton: View {
    let label: String
    var kind: ButtonKind = .normal
    var disabled = false
    /// Row-level actions on phones use the 34px input height instead of the 44px touch height.
    var compact = false
    let action: () -> Void
    @State private var hover = false

    public init(_ label: String, kind: ButtonKind = .normal, disabled: Bool = false, compact: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.kind = kind; self.disabled = disabled; self.compact = compact; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(Type.isPhone ? Type.label() : Type.buttonLabel())
                .kerning(0.5)
                .padding(.horizontal, Type.isPhone ? (compact ? 10 : 14) : 6)
                .frame(height: Type.isPhone ? (compact ? Tok.inputHeight : Tok.touchHeight) : Tok.buttonHeight)
                .foregroundStyle(fg)
                .background(bgColor)
                .overlay(Rectangle().stroke(borderColor, lineWidth: Tok.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hover = $0 }
    }

    private var fg: Color {
        switch kind {
        case .primary: return Tok.segOnText
        case .danger: return hover ? Tok.err : Tok.control
        case .normal: return hover ? Tok.text : Tok.control
        }
    }
    private var bgColor: Color { kind == .primary ? Tok.segOn : .clear }
    private var borderColor: Color {
        switch kind {
        case .primary: return Tok.segOn
        case .danger: return hover ? Tok.err : Tok.border
        case .normal: return hover ? Tok.text : Tok.border
        }
    }
}

/// A button that matches a 34px input when sitting in the same row.
public struct RowButton: View {
    let label: String
    var kind: ButtonKind = .normal
    var disabled = false
    let action: () -> Void
    @State private var hover = false
    public init(_ label: String, kind: ButtonKind = .normal, disabled: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.kind = kind; self.disabled = disabled; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(label.uppercased()).font(Type.label()).kerning(0.5)
                .padding(.horizontal, 12)
                .frame(height: Type.isPhone ? Tok.touchHeight : Tok.inputHeight)
                .foregroundStyle(kind == .primary ? Tok.segOnText : (hover ? Tok.text : Tok.control))
                .background(kind == .primary ? Tok.segOn : .clear)
                .overlay(Rectangle().stroke(kind == .primary ? Tok.segOn : (hover ? Tok.text : Tok.border), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.45 : 1).onHover { hover = $0 }
    }
}

// MARK: Fields

public enum FieldStyle { case text, mono, secure, code }

/// Label above, 34px input (44 on phone), 1px border, mono for data, hint under.
public struct OpsField: View {
    let label: String
    @Binding var text: String
    var style: FieldStyle = .text
    var hint: String? = nil
    var placeholder: String = ""
    var autofocus = false
    var onSubmit: (() -> Void)? = nil
    @FocusState private var focused: Bool

    public init(_ label: String, text: Binding<String>, style: FieldStyle = .text, hint: String? = nil,
                placeholder: String = "", autofocus: Bool = false, onSubmit: (() -> Void)? = nil) {
        self.label = label; self._text = text; self.style = style; self.hint = hint
        self.placeholder = placeholder; self.autofocus = autofocus; self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tok.s2) {
            if !label.isEmpty { Lbl(label) }
            Group {
                if style == .secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        #if os(iOS)
                        .keyboardType(style == .code ? .numberPad : .default)
                        .textInputAutocapitalization(.never)
                        #endif
                }
            }
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .font(style == .text ? Type.body() : Type.data())
            .foregroundStyle(Tok.text)
            .padding(.horizontal, Tok.s25)
            .frame(height: Type.isPhone ? Tok.touchHeight : Tok.inputHeight)
            .background(Tok.surface)
            .overlay(Rectangle().stroke(focused ? Tok.text : Tok.border, lineWidth: 1))
            .focused($focused)
            .onSubmit { onSubmit?() }
            if let hint { Text(hint).font(Type.hint()).foregroundStyle(Tok.text3) }
        }
        .onAppear { if autofocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } } }
    }
}

/// Multi-line notes.
public struct OpsTextArea: View {
    let label: String
    @Binding var text: String
    var minHeight: CGFloat = 96
    @FocusState private var focused: Bool
    public init(_ label: String, text: Binding<String>, minHeight: CGFloat = 96) {
        self.label = label; self._text = text; self.minHeight = minHeight
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Tok.s2) {
            if !label.isEmpty { Lbl(label) }
            TextEditor(text: $text)
                .font(Type.body()).foregroundStyle(Tok.text)
                .scrollContentBackground(.hidden)
                .padding(Tok.s2)
                .frame(minHeight: minHeight)
                .background(Tok.surface)
                .overlay(Rectangle().stroke(focused ? Tok.text : Tok.border, lineWidth: 1))
                .focused($focused)
        }
    }
}

// MARK: Segmented control

/// One bordered group, active segment inverted.
public struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    public init(_ options: [(T, String)], selection: Binding<T>) { self.options = options; self._selection = selection }
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                let on = opt.0 == selection
                Button { selection = opt.0 } label: {
                    Text(opt.1.uppercased()).font(Type.isPhone ? Type.label() : Type.buttonLabel()).kerning(0.5)
                        .padding(.horizontal, Type.isPhone ? 12 : 8)
                        .frame(height: Type.isPhone ? Tok.touchHeight : Tok.buttonHeight)
                        .foregroundStyle(on ? Tok.segOnText : Tok.control)
                        .background(on ? Tok.segOn : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rectangle().fill(Tok.border).frame(width: 1) }
            }
        }
        .fixedSize()
        .overlay(Rectangle().stroke(Tok.border, lineWidth: 1))
    }
}

// MARK: Status

public enum StatusKind { case confirmed, waiting, attention, broken }

/// 8px glyph + caps word. Expected states grey; states needing a person in text at 600.
public struct StatusMark: View {
    let kind: StatusKind
    let word: String
    var needsAction = false
    public init(_ kind: StatusKind, _ word: String, needsAction: Bool = false) {
        self.kind = kind; self.word = word; self.needsAction = needsAction
    }
    public var body: some View {
        HStack(spacing: Tok.s2) {
            glyph.frame(width: 8, height: 8)
            Text(word.uppercased()).font(Type.label()).kerning(0.6)
                .foregroundStyle(needsAction ? Tok.text : Tok.text3)
        }
    }
    @ViewBuilder private var glyph: some View {
        switch kind {
        case .confirmed: Rectangle().fill(needsAction ? Tok.text : Tok.text3)
        case .waiting: Rectangle().stroke(needsAction ? Tok.text : Tok.text3, lineWidth: 1)
        case .attention: Triangle().fill(Tok.warn)
        case .broken: Cross().stroke(Tok.err, lineWidth: 1.5)
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath(); return p
    }
}
struct Cross: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); return p
    }
}

// MARK: Panels

/// Bordered panel on surface, 16px padding, optional title-3 header.
public struct Panel<Content: View>: View {
    var title: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: () -> Content
    public init(title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.trailing = trailing; self.content = content
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Tok.s3) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { Text(title).font(Type.title3()).foregroundStyle(Tok.text) }
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content()
        }
        .padding(Tok.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.surface)
        .overlay(Rectangle().stroke(Tok.border, lineWidth: 1))
    }
}

/// KPI cell: key / value / sub.
public struct KPI: View {
    let key: String, value: String, sub: String?
    public init(_ key: String, _ value: String, _ sub: String? = nil) { self.key = key; self.value = value; self.sub = sub }
    public var body: some View {
        VStack(alignment: .leading, spacing: Tok.s2) {
            Lbl(key)
            Text(value).font(Type.dataLg()).foregroundStyle(Tok.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub ?? " ").font(Type.hint()).foregroundStyle(Tok.text3).lineLimit(1)
        }
        .padding(.vertical, Tok.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Top and bottom border, divider between cells.
public struct KPIStrip: View {
    let cells: [(String, String, String?)]
    public init(_ cells: [(String, String, String?)]) { self.cells = cells }
    public var body: some View {
        VStack(spacing: 0) {
            Rule()
            if Type.isPhone {
                ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                    KPI(c.0, c.1, c.2)
                    if i < cells.count - 1 { Rule(quiet: true) }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                        KPI(c.0, c.1, c.2).padding(.horizontal, Tok.s3)
                        if i < cells.count - 1 { Rectangle().fill(Tok.divider).frame(width: 1) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Rule()
        }
    }
}

/// A line of status text below a form: "Checking" in text-3, errors in err.
public struct StatusLine: View {
    let text: String?
    let isError: Bool
    public init(_ text: String?, isError: Bool = false) { self.text = text; self.isError = isError }
    public var body: some View {
        Text(text ?? " ").font(Type.meta()).foregroundStyle(isError ? Tok.err : Tok.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Module icons (section 08): 24px grid, 1.5px stroke, square corners, hollow at rest, filled when active.

public enum ModuleIcon { case cards, files, sync, settings }

public struct IconView: View {
    let icon: ModuleIcon
    let active: Bool
    var size: CGFloat = 20
    public init(_ icon: ModuleIcon, active: Bool, size: CGFloat = 20) { self.icon = icon; self.active = active; self.size = size }
    public var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 24
            let color = active ? Tok.text : Tok.text3
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s))
            }
            var stroke = StrokeStyle(lineWidth: 1.5 * s, lineCap: .square, lineJoin: .miter)
            stroke.miterLimit = 10
            switch icon {
            case .cards:
                // Two stacked cards
                if active {
                    ctx.fill(rect(3, 6, 14, 10), with: .color(color))
                    ctx.fill(rect(7, 10, 14, 10), with: .color(Tok.bg))
                    ctx.fill(rect(8.5, 11.5, 11, 7), with: .color(color))
                } else {
                    ctx.stroke(rect(3.75, 6.75, 12.5, 8.5), with: .color(color), style: stroke)
                    ctx.fill(rect(7, 10, 14, 10), with: .color(Tok.bg))
                    ctx.stroke(rect(7.75, 10.75, 12.5, 8.5), with: .color(color), style: stroke)
                }
            case .files:
                // Folder: tab above a body
                if active {
                    ctx.fill(rect(3, 5, 8, 4), with: .color(color))
                    ctx.fill(rect(3, 8, 18, 11), with: .color(color))
                } else {
                    ctx.stroke(rect(3.75, 5.75, 6.5, 3), with: .color(color), style: stroke)
                    ctx.fill(rect(3, 8, 18, 11), with: .color(Tok.bg))
                    ctx.stroke(rect(3.75, 8.75, 16.5, 9.5), with: .color(color), style: stroke)
                }
            case .sync:
                // Two opposing arrows
                var p = Path()
                p.move(to: CGPoint(x: 4 * s, y: 9 * s)); p.addLine(to: CGPoint(x: 20 * s, y: 9 * s))
                p.move(to: CGPoint(x: 16 * s, y: 5 * s)); p.addLine(to: CGPoint(x: 20 * s, y: 9 * s)); p.addLine(to: CGPoint(x: 16 * s, y: 13 * s))
                p.move(to: CGPoint(x: 20 * s, y: 15 * s)); p.addLine(to: CGPoint(x: 4 * s, y: 15 * s))
                p.move(to: CGPoint(x: 8 * s, y: 11 * s)); p.addLine(to: CGPoint(x: 4 * s, y: 15 * s)); p.addLine(to: CGPoint(x: 8 * s, y: 19 * s))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: (active ? 2.5 : 1.5) * s, lineCap: .square, lineJoin: .miter))
            case .settings:
                // Three sliders
                for (i, y) in [6.5, 12, 17.5].enumerated() {
                    var line = Path(); line.move(to: CGPoint(x: 3 * s, y: y * s)); line.addLine(to: CGPoint(x: 21 * s, y: y * s))
                    ctx.stroke(line, with: .color(color), style: stroke)
                    let kx: CGFloat = [8, 15, 11][i]
                    if active { ctx.fill(rect(kx - 2, y - 2.5, 4, 5), with: .color(color)) }
                    else {
                        ctx.fill(rect(kx - 2.75, y - 3.25, 5.5, 6.5), with: .color(Tok.bg))
                        ctx.stroke(rect(kx - 2, y - 2.5, 4, 5), with: .color(color), style: stroke)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

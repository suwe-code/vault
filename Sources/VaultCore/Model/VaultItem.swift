import Foundation

/// Any kind of data the user wants kept. A card is a title, a category used only
/// for the template and the icon, and an ordered list of labelled fields.
public struct VaultItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var category: ItemCategory
    public var fields: [VaultField]
    public var notes: String
    public var tags: [String]
    public var attachments: [Attachment]
    public var favourite: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    /// Tombstone. Deleted items are kept (without content) so a merge can propagate the deletion.
    public var deletedAt: Date?

    public init(id: UUID = UUID(), title: String, category: ItemCategory = .custom,
                fields: [VaultField] = [], notes: String = "", tags: [String] = [],
                attachments: [Attachment] = [], favourite: Bool = false,
                createdAt: Date = Date(), modifiedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id; self.title = title; self.category = category; self.fields = fields
        self.notes = notes; self.tags = tags; self.attachments = attachments; self.favourite = favourite
        self.createdAt = createdAt.vaultRounded; self.modifiedAt = modifiedAt.vaultRounded; self.deletedAt = deletedAt?.vaultRounded
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// Clears content and stamps the tombstone.
    public mutating func markDeleted(at date: Date = Date()) {
        title = ""; fields = []; notes = ""; tags = []; attachments = []; favourite = false
        deletedAt = date.vaultRounded; modifiedAt = date.vaultRounded
    }

    public mutating func touch(_ date: Date = Date()) { modifiedAt = date.vaultRounded }

    /// Text that search may match. Secret field values are deliberately excluded.
    public var searchText: String {
        var parts = [title, notes, category.label] + tags
        for f in fields where !f.kind.isSecret { parts.append(f.label); parts.append(f.value) }
        for f in fields where f.kind.isSecret { parts.append(f.label) }
        return parts.joined(separator: " ").lowercased()
    }
}

public struct VaultField: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String
    public var kind: FieldKind

    public init(id: UUID = UUID(), label: String, value: String = "", kind: FieldKind = .text) {
        self.id = id; self.label = label; self.value = value; self.kind = kind
    }
}

public enum FieldKind: String, Codable, CaseIterable, Sendable {
    case text       // plain, shown
    case secret     // hidden until revealed, copy clears clipboard
    case pin        // short secret, numeric keyboard
    case number     // mono, tabular
    case date
    case url
    case email
    case phone
    case otpSecret  // base32 seed; the app renders the live 6-digit code

    public var isSecret: Bool {
        switch self { case .secret, .pin, .otpSecret: return true; default: return false }
    }

    public var isMono: Bool {
        switch self { case .text, .url, .email: return false; default: return true }
    }

    public var label: String {
        switch self {
        case .text: return "TEXT"
        case .secret: return "SECRET"
        case .pin: return "PIN"
        case .number: return "NUMBER"
        case .date: return "DATE"
        case .url: return "URL"
        case .email: return "EMAIL"
        case .phone: return "PHONE"
        case .otpSecret: return "ONE-TIME CODE"
        }
    }
}

public enum ItemCategory: String, Codable, CaseIterable, Sendable {
    case bank, card, login, identity, note, custom

    public var label: String {
        switch self {
        case .bank: return "BANK"
        case .card: return "CARD"
        case .login: return "LOGIN"
        case .identity: return "IDENTITY"
        case .note: return "NOTE"
        case .custom: return "CUSTOM"
        }
    }
}

public struct Attachment: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var filename: String
    public var mimeType: String
    public var data: Data
    public var addedAt: Date

    public init(id: UUID = UUID(), filename: String, mimeType: String, data: Data, addedAt: Date = Date()) {
        self.id = id; self.filename = filename; self.mimeType = mimeType; self.data = data; self.addedAt = addedAt.vaultRounded
    }
}

/// Starting field sets. Every field stays editable, removable and reorderable.
public enum Templates {
    public static func fields(for category: ItemCategory) -> [VaultField] {
        switch category {
        case .bank:
            return [
                .init(label: "Bank"), .init(label: "Account holder"),
                .init(label: "Account number", kind: .number), .init(label: "IFSC", kind: .number),
                .init(label: "Customer ID", kind: .number), .init(label: "Branch"),
                .init(label: "Net banking user"), .init(label: "Net banking password", kind: .secret),
                .init(label: "Transaction PIN", kind: .pin), .init(label: "UPI PIN", kind: .pin),
                .init(label: "Registered phone", kind: .phone),
            ]
        case .card:
            return [
                .init(label: "Bank"), .init(label: "Card number", kind: .number),
                .init(label: "Name on card"), .init(label: "Expiry", kind: .number),
                .init(label: "CVV", kind: .pin), .init(label: "ATM PIN", kind: .pin),
                .init(label: "Linked account"),
            ]
        case .login:
            return [
                .init(label: "Site", kind: .url), .init(label: "Username or email", kind: .email),
                .init(label: "Password", kind: .secret), .init(label: "One-time code seed", kind: .otpSecret),
                .init(label: "Recovery email", kind: .email), .init(label: "Recovery phone", kind: .phone),
                .init(label: "Backup codes", kind: .secret),
            ]
        case .identity:
            return [
                .init(label: "Document"), .init(label: "Number", kind: .number),
                .init(label: "Name as printed"), .init(label: "Date of birth", kind: .date),
                .init(label: "Issued", kind: .date), .init(label: "Expires", kind: .date),
            ]
        case .note:
            return []
        case .custom:
            return [.init(label: "Value")]
        }
    }
}

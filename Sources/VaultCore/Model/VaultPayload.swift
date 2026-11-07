import Foundation

/// Everything inside the encrypted body.
public struct VaultPayload: Codable, Equatable, Sendable {
    public var items: [VaultItem]
    public var deviceName: String
    public var savedAt: Date
    /// One-time-code seed shared by every device, so a single authenticator entry works everywhere.
    public var totpSecret: Data?

    public init(items: [VaultItem] = [], deviceName: String = "", savedAt: Date = Date(), totpSecret: Data? = nil) {
        self.items = items; self.deviceName = deviceName; self.savedAt = savedAt.vaultRounded; self.totpSecret = totpSecret
    }

    public var liveItems: [VaultItem] { items.filter { !$0.isDeleted } }

    /// Drops tombstones older than `retention` so the file does not grow forever.
    public mutating func pruneTombstones(olderThan retention: TimeInterval = 90 * 86400, now: Date = Date()) {
        items.removeAll { item in
            if let d = item.deletedAt { return now.timeIntervalSince(d) > retention }
            return false
        }
    }
}

public struct MergeSummary: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var deleted = 0
    public var unchanged = 0
    public var total: Int { added + updated + deleted }
}

/// Last-writer-wins per card, with tombstones. Deterministic and symmetric:
/// merging A into B gives the same set as merging B into A.
public enum VaultMerge {
    public static func merge(local: [VaultItem], incoming: [VaultItem]) -> (items: [VaultItem], summary: MergeSummary) {
        var byID: [UUID: VaultItem] = [:]
        for item in local { byID[item.id] = item }
        var summary = MergeSummary()
        for inc in incoming {
            guard let cur = byID[inc.id] else {
                byID[inc.id] = inc
                if inc.isDeleted { summary.unchanged += 1 } else { summary.added += 1 }
                continue
            }
            if inc.modifiedAt > cur.modifiedAt {
                byID[inc.id] = inc
                if inc.isDeleted && !cur.isDeleted { summary.deleted += 1 }
                else if !inc.isDeleted { summary.updated += 1 }
                else { summary.unchanged += 1 }
            } else if inc.modifiedAt == cur.modifiedAt && inc != cur {
                // Same timestamp, different content: keep the deterministic winner.
                let winner = inc.isDeleted || (!cur.isDeleted && inc.id.uuidString < cur.id.uuidString) ? inc : cur
                if winner != cur { byID[inc.id] = winner; summary.updated += 1 } else { summary.unchanged += 1 }
            } else {
                summary.unchanged += 1
            }
        }
        let items = byID.values.sorted { a, b in
            if a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
            return a.id.uuidString < b.id.uuidString
        }
        return (items, summary)
    }
}

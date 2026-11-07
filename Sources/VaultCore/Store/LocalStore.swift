import Foundation

/// Where the encrypted vault lives on this device. Writes are atomic and the
/// previous version is kept as a fallback copy.
public struct LocalStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("vault.vault") }
    public var previousURL: URL { directory.appendingPathComponent("vault.previous.vault") }

    public init(directory: URL? = nil) {
        if let directory { self.directory = directory } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("VAULT", isDirectory: true)
        }
    }

    public func exists() -> Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    public func load() throws -> VaultFile? {
        guard exists() else { return nil }
        return try VaultFile.parse(try Data(contentsOf: fileURL))
    }

    public func save(_ file: VaultFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try file.serialized()
        if exists() {
            _ = try? FileManager.default.removeItem(at: previousURL)
            try? FileManager.default.copyItem(at: fileURL, to: previousURL)
        }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: previousURL)
    }
}

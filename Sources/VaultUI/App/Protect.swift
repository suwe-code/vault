import Foundation
import UniformTypeIdentifiers
import PDFKit
#if canImport(AppKit)
import AppKit
#endif

/// Wraps a plain copy in a password the recipient types once.
///
///   PDF and images  →  an encrypted PDF (AES, opens in any PDF viewer, phone or desktop).
///   Anything else   →  a password-protected ZIP (Mac only; built with the system zip tool).
///
/// The recipient needs the password you set, sent by another channel.
enum Protect {
    enum Failure: LocalizedError {
        case unreadable, unsupported
        var errorDescription: String? {
            switch self {
            case .unreadable: return "File could not be read for protection"
            case .unsupported: return "Protected sharing for this kind of file is Mac only"
            }
        }
    }

    /// Writes the protected file next to `url` and returns it.
    static func wrap(_ url: URL, typeID: String, password: String) throws -> URL {
        let t = UTType(typeID) ?? UTType(filenameExtension: url.pathExtension) ?? .data
        if t.conforms(to: .pdf) || t.conforms(to: .image) { return try pdf(url, isPDF: t.conforms(to: .pdf), password: password) }
        #if canImport(AppKit)
        return try zip(url, password: password)
        #else
        throw Failure.unsupported
        #endif
    }

    private static func pdf(_ url: URL, isPDF: Bool, password: String) throws -> URL {
        let doc: PDFDocument
        if isPDF {
            guard let d = PDFDocument(url: url) else { throw Failure.unreadable }
            doc = d
        } else {
            #if canImport(AppKit)
            guard let img = NSImage(contentsOf: url), let page = PDFPage(image: img) else { throw Failure.unreadable }
            #else
            guard let img = UIImage(contentsOfFile: url.path), let page = PDFPage(image: img) else { throw Failure.unreadable }
            #endif
            doc = PDFDocument(); doc.insert(page, at: 0)
        }
        let base = url.deletingPathExtension().lastPathComponent
        let out = url.deletingLastPathComponent().appendingPathComponent("\(base).protected.pdf")
        let ok = doc.write(to: out, withOptions: [
            .userPasswordOption: password,
            .ownerPasswordOption: password,
            PDFDocumentWriteOption(rawValue: kCGPDFContextEncryptionKeyLength as String): 128,
        ])
        guard ok else { throw Failure.unreadable }
        return out
    }

    #if canImport(AppKit)
    private static func zip(_ url: URL, password: String) throws -> URL {
        let base = url.deletingPathExtension().lastPathComponent
        let out = url.deletingLastPathComponent().appendingPathComponent("\(base).protected.zip")
        try? FileManager.default.removeItem(at: out)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = url.deletingLastPathComponent()
        p.arguments = ["-q", "-j", "-P", password, out.path, url.lastPathComponent]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) else { throw Failure.unreadable }
        return out
    }
    #endif
}

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// QR rendered dark on a white well so it scans in dark mode too.
public struct QRView: View {
    let text: String
    var size: CGFloat = 180
    public init(_ text: String, size: CGFloat = 180) { self.text = text; self.size = size }
    public var body: some View {
        Group {
            if let img = Self.image(for: text) {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(1, contentMode: .fit)
            } else { Rectangle().fill(Tok.recessed) }
        }
        .frame(width: size, height: size)
        .padding(Tok.s3)
        .background(Color.white)
        .overlay(Rectangle().stroke(Tok.border, lineWidth: 1))
    }
    static func image(for text: String) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

public extension UTType {
    /// Declared in each app's Info.plist as an exported type.
    static let vaultFile = UTType(exportedAs: "com.suwe.vault.file", conformingTo: .data)
}

/// Wraps already-encrypted bytes for the system save panel.
public struct VaultExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.vaultFile] }
    public static var writableContentTypes: [UTType] { [.vaultFile] }
    public var data: Data
    public init(data: Data) { self.data = data }
    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

public struct TextExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.plainText] }
    public var text: String
    public init(text: String) { self.text = text }
    public init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

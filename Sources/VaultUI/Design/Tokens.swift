import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// SPEC-OPS design tokens (Design v2.3, section 03 and 11).
/// Light values are Doc mode, dark values are Ops mode. Same names, different values.
public enum Tok {
    public static let bg        = dyn(light: 0xf4f4f4, dark: 0x0d0d0d)
    public static let surface   = dyn(light: 0xffffff, dark: 0x1a1a1a)
    public static let elevated  = dyn(light: 0xffffff, dark: 0x222222)
    public static let recessed  = dyn(light: 0xfafafa, dark: 0x141414)
    public static let border    = dyn(light: 0xd6d6d6, dark: 0x2a2a2a)
    public static let borderQuiet = dyn(light: 0xe6e6e6, dark: 0x242424)
    public static let divider   = dyn(light: 0xe6e6e6, dark: 0x1f1f1f)
    public static let text      = dyn(light: 0x0d0d0d, dark: 0xfafafa)
    public static let text2     = dyn(light: 0x5c5c5c, dark: 0x9a9a9a)
    public static let text3     = dyn(light: 0x8a8a8a, dark: 0x6b6b6b)
    public static let control   = dyn(light: 0x3a3a3a, dark: 0xb5b5b5)
    public static let segOn     = dyn(light: 0x0d0d0d, dark: 0xb5b5b5)
    public static let segOnText = dyn(light: 0xffffff, dark: 0x000000)
    public static let ok        = Color(hex: 0x55a06e)
    public static let warn      = Color(hex: 0xc28e3c)
    public static let err       = Color(hex: 0xc05a52)

    // Spacing, 4px base (section 05)
    public static let s1: CGFloat = 4, s2: CGFloat = 8, s25: CGFloat = 10, s3: CGFloat = 12
    public static let s4: CGFloat = 16, s5: CGFloat = 20, s6: CGFloat = 24, s7: CGFloat = 28
    public static let s12: CGFloat = 48, s18: CGFloat = 72

    // Layout (section 06, 13)
    public static let appColumn: CGFloat = 880
    /// Smallest side of a credentials square; the row is split evenly into as many as fit.
    public static let cardMin: CGFloat = 250
    /// Card height: header plus three field rows; more rows scroll inside the card.
    public static let cardHeight: CGFloat = 212
    /// File tiles: preview on top, name and actions below.
    public static let fileMin: CGFloat = 200
    public static let fileHeight: CGFloat = 196
    public static let phoneGutter: CGFloat = 24
    public static let inputHeight: CGFloat = 34
    public static let buttonHeight: CGFloat = 18
    public static let touchHeight: CGFloat = 44
    public static let hairline: CGFloat = 1

    static func dyn(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #else
        return Color(NSColor(name: nil) { app in
            app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #endif
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
#else
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
#endif

/// Type scale (section 04). Geist for titles and reading, Geist Mono for data.
public enum Type {
    public static func title1() -> Font { .custom("Geist-Medium", size: isPhone ? 24 : 30) }
    public static func title2() -> Font { .custom("Geist-Medium", size: 22) }
    public static func title3() -> Font { .custom("Geist-Medium", size: 16) }
    public static func heading() -> Font { .custom("Geist-Medium", size: 14) }
    public static func body() -> Font { .custom("Geist-Regular", size: 13) }
    public static func bodyStrong() -> Font { .custom("Geist-Medium", size: 13) }
    public static func cell() -> Font { .custom("Geist-Regular", size: 12.5) }
    public static func meta() -> Font { .custom("Geist-Regular", size: 11.5) }
    public static func hint() -> Font { .custom("Geist-Regular", size: 11) }
    public static func label() -> Font { .custom("Geist-SemiBold", size: 10) }
    public static func buttonLabel() -> Font { .custom("Geist-SemiBold", size: 9) }
    public static func dataLg() -> Font { .custom("GeistMono-Medium", size: 18) }
    public static func data() -> Font { .custom("GeistMono-Medium", size: 13) }
    public static func dataBody() -> Font { .custom("GeistMono-Regular", size: 12.5) }
    public static func tag() -> Font { .custom("GeistMono-Medium", size: 10) }
    public static func sig() -> Font { .custom("GeistMono-Medium", size: 10) }

    /// Forces the phone layout when rendering previews on a Mac.
    nonisolated(unsafe) public static var phoneOverride: Bool? = nil

    public static var isPhone: Bool {
        if let phoneOverride { return phoneOverride }
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
}

/// Registers the bundled Geist fonts once. Call at app launch.
public enum Fonts {
    nonisolated(unsafe) private static var registered = false
    public static func register() {
        guard !registered else { return }
        registered = true
        let names = ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium"]
        for n in names {
            guard let url = Bundle.module.url(forResource: n, withExtension: "ttf", subdirectory: "Fonts")
                    ?? Bundle.module.url(forResource: n, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Section 09: YYYYMMDDTTTT, 24h, nothing inserted.
public enum Fmt {
    public static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMddHHmm"
        return f.string(from: d)
    }
    public static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }
}

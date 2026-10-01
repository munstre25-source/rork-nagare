import CoreText
import UIKit

/// Registers the bundled Noto Sans JP fonts and resolves the Japanese font name with a Hiragino fallback.
enum FontRegistry {
    static let notoRegular = "NotoSansJP-Regular"
    static let notoBold = "NotoSansJP-Bold"
    private static var isNotoAvailable = false

    static func registerFonts() {
        for name in [notoRegular, notoBold] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        isNotoAvailable = UIFont(name: notoRegular, size: 12) != nil && UIFont(name: notoBold, size: 12) != nil
        if !isNotoAvailable {
            print("[Jojo] Noto Sans JP unavailable, falling back to Hiragino Sans")
        }
    }

    static func fontName(bold: Bool) -> String {
        if isNotoAvailable { return bold ? notoBold : notoRegular }
        return bold ? "HiraginoSans-W6" : "HiraginoSans-W3"
    }
}

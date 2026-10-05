import SwiftUI
import UIKit

extension UIColor {
    /// Creates a color from a `#RRGGBB` hex string.
    nonisolated convenience init(hex: String, alpha: CGFloat = 1) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        guard value.count == 6 else {
            self.init(white: 0.5, alpha: alpha)
            return
        }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A color that resolves differently in light and dark mode.
    nonisolated static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    // MARK: Backgrounds
    /// Pure black for the video frame itself — never lightens with appearance.
    static let bgPlayer = Color(hex: "#000000")
    /// Page behind a playing clip. Cream in light mode, pure black in dark mode.
    static let watchBackground = Color.adaptive(light: "#FFF6EE", dark: "#000000")
    /// Raised chrome under the transcript / feed cards. Cream in light, near-black in dark.
    static let bgSurfaceDark = Color.adaptive(light: "#FFFFFF", dark: "#121212")
    static let bgElevatedDark = Color.adaptive(light: "#FFFFFF", dark: "#1C1C1E")
    static let hairlineDark = Color.adaptive(light: "#F2E2D1", dark: "#2A2A2A")
    /// App page background — cream in light; deep night (icon sky) in dark.
    static let canvas = Color.adaptive(light: "#FFF6EE", dark: "#0B0816")
    static let card = Color.adaptive(light: "#FFFFFF", dark: "#1C1C1E")
    static let cardStroke = Color.adaptive(light: "#F2E2D1", dark: "#2A2A2A")
    static let fieldFill = Color.adaptive(light: "#F7E8D8", dark: "#1C1C1E")
    /// Active karaoke line card (Kiku-style raised surface).
    static let transcriptCard = Color.adaptive(light: "#FFFFFF", dark: "#2C2C2E")
    /// Soft sakura-night lift behind the active line.
    static let activeLineGlow = Color(hex: "#2A1452").opacity(0.22)

    // MARK: Brand accent
    /// Plum sakura marks. Deep on cream, light wisteria on black so underlines and icons stay readable.
    static let sakuraPink = Color.adaptive(light: "#7A4684", dark: "#E8D0F2")
    /// Same mark color. Fills that carry white type use `sakuraButton` instead.
    static let sakuraPinkDeep = sakuraPink
    /// Wisteria petal. Pale on cream, a solid mid plum on black so white type still reads.
    static let sakuraPinkLight = Color.adaptive(light: "#E3D2E8", dark: "#6B4580")
    static let sakuraPinkSoft = sakuraPinkLight
    /// Button and badge fills. Deep plum in both appearances so the white label stays clear.
    static let sakuraButton = Color(hex: "#7A4684")

    /// Interactive chrome (tabs, toggles, selection, charts) — sakura, not orange.
    static let brandAccent = sakuraPink
    static let brandAccentSoft = sakuraPinkSoft
    static let brandAccentLight = sakuraPinkLight
    static let brandAccentDeep = sakuraPinkDeep

    /// Legacy names kept so call sites compile; they now resolve to sakura accent.
    static let jojoOrange = brandAccent
    static let jojoOrangeSoft = brandAccentSoft
    static let jojoOrangeLight = brandAccentLight
    /// Was hinomaru red — now deep sakura so chrome never reintroduces orange/vermilion.
    static let jojoVermilion = brandAccentDeep

    /// Main-app chrome. Same sakura as the icon and onboarding, so the accent never shifts after the first screen.
    static let designOrange = sakuraPink
    static let designOrangeDeep = sakuraPinkDeep

    /// Solid plum fill for controls with white type.
    static let sakuraFill = LinearGradient(
        colors: [Color.sakuraButton, Color.sakuraButton],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sakuraBar = LinearGradient(
        colors: [Color.sakuraButton, Color.sakuraButton],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: Brand surfaces (icon: sakura-night sky, cream paper)
    /// Cream paper surfaces in light mode.
    static let jojoCream = Color(hex: "#FFF6EE")
    /// One step warmer than `jojoCream`, for layered washes.
    static let jojoCreamDeep = Color(hex: "#FDEBDA")
    static let jojoInk = Color(hex: "#2A2A2A")
    static let jojoInkSoft = Color(hex: "#6B6B6B")
    static let jojoInkFaint = Color(hex: "#A79C92")
    /// Card fill / hairline on the cream surface.
    static let jojoPaper = Color(hex: "#FFFFFF")
    static let jojoPaperStroke = Color(hex: "#F2E2D1")
    static let jojoBlossom = Color(hex: "#E3D2E8")
    static let jojoGold = Color(hex: "#F5C542")

    // MARK: Night-sakura (matches the iOS app icon atmosphere)
    static let nightIndigo = Color(hex: "#140C2E")
    static let nightViolet = Color(hex: "#2A1452")
    static let nightPlum = Color(hex: "#4A1D6B")
    static let neonMagenta = Color.adaptive(light: "#7A4684", dark: "#E8D0F2")
    static let lanternAmber = Color(hex: "#FFB347")

    // MARK: Readable secondary (light theme was washing out on cream/white)
    /// Furigana / romaji — quieter than the English line, still readable.
    static let textSecondary = Color.adaptive(light: "#3A3A3C", dark: "#C7C7CC")
    static let textTertiary = Color.adaptive(light: "#5C5C5C", dark: "#AEAEB2")
    /// English under a line, and the reading on a card. Near-black on cream, near-white on night.
    static let translationText = Color.adaptive(light: "#1C1C1E", dark: "#F5F5F7")

    // MARK: Word states / POS underlines
    static let tappableBlue = Color.adaptive(light: "#2563EB", dark: "#4C8DFF")
    static let spokenGreen = Color.adaptive(light: "#15803D", dark: "#34C759")
    static let lookedUpOrange = Color.sakuraPinkSoft
    /// Content words (noun, verb, adjective) — blue underline.
    static let posContentBlue = Color.adaptive(light: "#2563EB", dark: "#3B82F6")
    /// Function words (particle, auxiliary, copula) — sakura underline (icon accent).
    static let posParticleOrange = Color.sakuraPink

    // MARK: SRS
    static let againBackground = Color(hex: "#FFD9DE")
    static let againText = Color(hex: "#C81E3A")
    static let goodBackground = Color(hex: "#1E9E4A")
    static let goodText = Color.white

    // MARK: Pills
    static let posPill = Color.adaptive(light: "#E6E6EB", dark: "#3A3A3C")
    static let posPillText = Color.adaptive(light: "#3A3A3C", dark: "#D1D1D6")
    static let jlptPill = Color(hex: "#1F7A3E")
    static let jlptPillText = Color.white

    // MARK: Definition tints
    static let definitionTints: [Color] = [
        .adaptive(light: "#EAF1FB", dark: "#1E2733"),
        .adaptive(light: "#F1F1F4", dark: "#23252B"),
        .adaptive(light: "#F7EDF6", dark: "#2A2230")
    ]
}

/// Shared animation curves so feed, popup and tabs feel like one product.
enum Motion {
    static let lineAdvance = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let popupSpring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let tabSlide = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let cardFlip = Animation.spring(response: 0.45, dampingFraction: 0.86)
    static let tapBounce = Animation.spring(response: 0.28, dampingFraction: 0.55)
}

/// Spacing scale.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radius scale.
enum Radius {
    static let pill: CGFloat = 10
    static let button: CGFloat = 16
    static let card: CGFloat = 18
    static let sheet: CGFloat = 20
}

/// Typography helpers. Japanese uses bundled Noto Sans JP (fallback Hiragino Sans); English uses SF Pro.
enum JojoFont {
    static func jp(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(FontRegistry.fontName(bold: bold), size: size, relativeTo: style)
    }
}

extension Token {
    /// Kiku-style underline: blue for content words, orange for particles / auxiliaries / copula.
    var underlineColor: Color {
        let key = pos.lowercased()
        switch key {
        case "particle", "auxiliary", "copula", "suffix":
            return .posParticleOrange
        default:
            return .posContentBlue
        }
    }
}

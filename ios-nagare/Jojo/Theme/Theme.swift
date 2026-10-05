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

/// Which accent and which paper the main app is painting. Read by the brand colors at draw time.
enum JojoPalette {
    private static let themeKey = "jojo.accent"
    private static let schemeKey = "jojo.scheme"

    static var theme: AccentTheme = .sakura
    static var scheme: JojoScheme = .dark

    static func activate(theme: AccentTheme, scheme: JojoScheme) {
        self.theme = theme
        self.scheme = scheme
        UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
        UserDefaults.standard.set(scheme.rawValue, forKey: schemeKey)
    }

    /// Onboarding always paints sakura on the night page.
    static func activateOnboarding() {
        activate(theme: .sakura, scheme: .dark)
    }

    /// A color for the accent and appearance that are active right now.
    /// Resolved immediately so switching Sakura, Purple, or Orange repaints every screen.
    static func color(
        sakuraLight: String, sakuraDark: String,
        plumLight: String, plumDark: String,
        orangeLight: String, orangeDark: String
    ) -> Color {
        let hex: String
        switch (theme, scheme) {
        case (.sakura, .light): hex = sakuraLight
        case (.sakura, .dark): hex = sakuraDark
        case (.plum, .light): hex = plumLight
        case (.plum, .dark): hex = plumDark
        case (.orange, .light): hex = orangeLight
        case (.orange, .dark): hex = orangeDark
        }
        return Color(hex: hex)
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
    /// Page behind a playing clip. White in light mode, pure black in dark mode.
    static let watchBackground = Color.adaptive(light: "#FFFFFF", dark: "#000000")
    /// Raised chrome under the transcript / feed cards. White in light, near-black in dark.
    static let bgSurfaceDark = Color.adaptive(light: "#FFFFFF", dark: "#121212")
    static let bgElevatedDark = Color.adaptive(light: "#FFFFFF", dark: "#1C1C1E")
    static let hairlineDark = Color.adaptive(light: "#E5E5EA", dark: "#2A2A2A")
    /// App page background — white in light; deep night (icon sky) in dark.
    static let canvas = Color.adaptive(light: "#FFFFFF", dark: "#0B0816")
    static let card = Color.adaptive(light: "#FFFFFF", dark: "#1C1C1E")
    static let cardStroke = Color.adaptive(light: "#E5E5EA", dark: "#2A2A2A")
    static let fieldFill = Color.adaptive(light: "#F2F2F7", dark: "#1C1C1E")
    /// Active karaoke line card (Kiku-style raised surface).
    static let transcriptCard = Color.adaptive(light: "#FFFFFF", dark: "#2C2C2E")
    /// Soft lift behind the active karaoke line, in the active accent.
    static var activeLineGlow: Color { LearningInk.glow.opacity(0.55) }

    // MARK: Brand accent
    /// Marks, underlines, and icons. Each theme picks a shade that stays readable on its page.
    static var sakuraPink: Color { JojoPalette.color(
        sakuraLight: "#C2186A", sakuraDark: "#FF7EB8",
        plumLight: "#7A4684", plumDark: "#E8D0F2",
        orangeLight: "#C45C00", orangeDark: "#FFB020"
    ) }
    static var sakuraPinkDeep: Color { sakuraPink }
    /// Soft chips. Pale on white, a solid dark tint at night so white type still reads.
    static var sakuraPinkLight: Color { JojoPalette.color(
        sakuraLight: "#F8D0E4", sakuraDark: "#6A2458",
        plumLight: "#E3D2E8", plumDark: "#5C3A72",
        orangeLight: "#F8E0C4", orangeDark: "#6B3A12"
    ) }
    static var sakuraPinkSoft: Color { sakuraPinkLight }
    /// Fills that carry a white label.
    static var sakuraButton: Color { JojoPalette.color(
        sakuraLight: "#E21888", sakuraDark: "#E21888",
        plumLight: "#7A4684", plumDark: "#7A4684",
        orangeLight: "#D35400", orangeDark: "#D35400"
    ) }

    /// Interactive chrome (tabs, toggles, selection, charts). Follows the selected accent.
    static var brandAccent: Color { sakuraPink }
    static var brandAccentSoft: Color { sakuraPinkSoft }
    static var brandAccentLight: Color { sakuraPinkLight }
    static var brandAccentDeep: Color { sakuraPinkDeep }

    /// Legacy names kept so call sites compile. They follow the selected accent.
    static var jojoOrange: Color { brandAccent }
    static var jojoOrangeSoft: Color { brandAccentSoft }
    static var jojoOrangeLight: Color { brandAccentLight }
    static var jojoVermilion: Color { brandAccentDeep }

    /// Main-app chrome. Follows Sakura, Purple, or Orange with the light or dark page.
    static var designOrange: Color { sakuraPink }
    static var designOrangeDeep: Color { sakuraPinkDeep }

    /// Solid accent fill for controls with white type.
    static var sakuraFill: LinearGradient {
        LinearGradient(
            colors: [Color.sakuraButton, Color.sakuraButton],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    static var sakuraBar: LinearGradient {
        LinearGradient(
            colors: [Color.sakuraButton, Color.sakuraButton],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

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
    static var neonMagenta: Color { JojoPalette.color(
        sakuraLight: "#C2186A", sakuraDark: "#FF7EB8",
        plumLight: "#7A4684", plumDark: "#E8D0F2",
        orangeLight: "#C45C00", orangeDark: "#FFB020"
    ) }
    static let lanternAmber = Color(hex: "#FFB347")

    // MARK: Readable secondary (light theme was washing out on cream/white)
    /// Furigana / romaji — quieter than the English line, still readable.
    static let textSecondary = Color.adaptive(light: "#3A3A3C", dark: "#C7C7CC")
    static let textTertiary = Color.adaptive(light: "#5C5C5C", dark: "#AEAEB2")
    /// English under a line, and the reading on a card. Near-black on cream, near-white on night.
    static let translationText = Color.adaptive(light: "#1C1C1E", dark: "#F5F5F7")

    // MARK: Word states / POS underlines
    static var tappableBlue: Color { LearningInk.content }
    static var spokenGreen: Color { LearningInk.known }
    static var lookedUpOrange: Color { LearningInk.familiar }
    /// Content words (noun, verb, adjective).
    static var posContentBlue: Color { LearningInk.content }
    /// Function words (particle, auxiliary, copula).
    static var posParticleOrange: Color { LearningInk.particle }

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

/// Jewel colors for Japanese, karaoke, and the dictionary. Each accent has a white-page set and a night set.
enum LearningInk {
    /// Kanji and kana at rest. Near-black on white, white on night, for every accent.
    static var japanese: Color { JojoPalette.color(
        sakuraLight: "#1A1020", sakuraDark: "#FFFFFF",
        plumLight: "#1A1024", plumDark: "#FFFFFF",
        orangeLight: "#1C1208", orangeDark: "#FFFFFF"
    ) }
    /// Reading above a word.
    static var furigana: Color { JojoPalette.color(
        sakuraLight: "#C2186A", sakuraDark: "#FFB7D8",
        plumLight: "#7A4684", plumDark: "#E8C8FF",
        orangeLight: "#C45C00", orangeDark: "#FFD7A1"
    ) }
    /// Romaji under a word.
    static var romaji: Color { JojoPalette.color(
        sakuraLight: "#8A3A62", sakuraDark: "#F3C6DC",
        plumLight: "#5C3A72", plumDark: "#D4B8EE",
        orangeLight: "#8A4E12", orangeDark: "#F6C48A"
    ) }
    /// Nouns, verbs, and adjectives.
    static var content: Color { JojoPalette.color(
        sakuraLight: "#007EA8", sakuraDark: "#5CEBFF",
        plumLight: "#6B2FA0", plumDark: "#C084FF",
        orangeLight: "#D35400", orangeDark: "#FFB020"
    ) }
    /// Particles and other function words.
    static var particle: Color { JojoPalette.color(
        sakuraLight: "#E21888", sakuraDark: "#FF5CAA",
        plumLight: "#C43B86", plumDark: "#FF7AD9",
        orangeLight: "#C2186A", orangeDark: "#FF6B8A"
    ) }
    /// The word currently being spoken.
    static var spoken: Color { JojoPalette.color(
        sakuraLight: "#C45C00", sakuraDark: "#FFE14A",
        plumLight: "#A15C00", plumDark: "#F6E27F",
        orangeLight: "#0B6E8A", orangeDark: "#5CEBFF"
    ) }
    /// A word the learner marked known.
    static var known: Color { JojoPalette.color(
        sakuraLight: "#0B8A4C", sakuraDark: "#5DFFB0",
        plumLight: "#0E7A45", plumDark: "#7DFFC3",
        orangeLight: "#0E7A45", orangeDark: "#6DFFB0"
    ) }
    /// Saved or familiar, quieter than the spoken word.
    static var familiar: Color { JojoPalette.color(
        sakuraLight: "#C2186A", sakuraDark: "#FF8AD4",
        plumLight: "#7A4684", plumDark: "#E8D0F2",
        orangeLight: "#C45C00", orangeDark: "#FF8A3D"
    ) }
    /// English under a karaoke line. Dark on white for Sakura, Purple, and Orange.
    static var english: Color { JojoPalette.color(
        sakuraLight: "#3A2A32", sakuraDark: "#FFD0E6",
        plumLight: "#3A2A44", plumDark: "#EBD6FF",
        orangeLight: "#4A3828", orangeDark: "#FFE0C2"
    ) }
    /// Glow behind the active line and the spoken pulse.
    static var glow: Color { JojoPalette.color(
        sakuraLight: "#E21888", sakuraDark: "#FF4FA3",
        plumLight: "#7A4684", plumDark: "#C084FF",
        orangeLight: "#D35400", orangeDark: "#FFB020"
    ) }

    /// The dictionary card stays on a night plate in both appearances, so these jewels stay luminous.
    static var dictionaryPlate: Color { JojoPalette.color(
        sakuraLight: "#140C18", sakuraDark: "#140C18",
        plumLight: "#120C1C", plumDark: "#120C1C",
        orangeLight: "#1A1008", orangeDark: "#1A1008"
    ) }
    static var dictionaryWord: Color { JojoPalette.color(
        sakuraLight: "#FF7EB8", sakuraDark: "#FF7EB8",
        plumLight: "#E8D0F2", plumDark: "#E8D0F2",
        orangeLight: "#FFB020", orangeDark: "#FFB020"
    ) }
    static var dictionaryReading: Color { JojoPalette.color(
        sakuraLight: "#FFB7D8", sakuraDark: "#FFB7D8",
        plumLight: "#C084FF", plumDark: "#C084FF",
        orangeLight: "#FFD7A1", orangeDark: "#FFD7A1"
    ) }
    static var dictionaryGloss: Color { JojoPalette.color(
        sakuraLight: "#FFE14A", sakuraDark: "#FFE14A",
        plumLight: "#F6E27F", plumDark: "#F6E27F",
        orangeLight: "#FFD7A1", orangeDark: "#FFD7A1"
    ) }
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

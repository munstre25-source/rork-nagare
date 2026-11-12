import SwiftUI
import UIKit
import Observation

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

    @Observable
    fileprivate final class PaletteState {
        var theme: AccentTheme = .amber
        var scheme: JojoScheme = .dark
    }

    private static let state = PaletteState()
    static var theme: AccentTheme { state.theme }
    static var scheme: JojoScheme { state.scheme }

    static func activate(theme: AccentTheme, scheme: JojoScheme) {
        state.theme = theme
        state.scheme = scheme
        UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
        UserDefaults.standard.set(scheme.rawValue, forKey: schemeKey)
    }

    /// New learners begin with the warm Amber identity; they can still pick Sakura later.
    static func activateOnboarding() {
        activate(theme: .amber, scheme: .dark)
    }

    /// A color for the accent and appearance that are active right now.
    /// Resolved immediately so switching Sakura or Amber repaints every screen.
    static func color(
        sakuraLight: String, sakuraDark: String,
        amberLight: String, amberDark: String
    ) -> Color {
        let hex: String
        switch (theme, scheme) {
        case (.sakura, .light): hex = sakuraLight
        case (.sakura, .dark): hex = sakuraDark
        case (.amber, .light): hex = amberLight
        case (.amber, .dark): hex = amberDark
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
    /// Video chrome needs contrast against footage, regardless of the page appearance.
    static let videoControlBackground = Color.black.opacity(0.72)
    static var videoControlAccent: Color {
        switch JojoPalette.theme {
        case .sakura: Color(hex: "#FF7EB8")
        case .amber: Color(hex: "#FFB020")
        }
    }
    /// Page behind a playing clip. White in light mode, pure black in dark mode.
    static let watchBackground = Color.adaptive(light: "#FFFFFF", dark: "#000000")
    /// Raised chrome under the transcript / feed cards. White in light, near-black in dark.
    static let bgSurfaceDark = Color.adaptive(light: "#FFFFFF", dark: "#121212")
    static let bgElevatedDark = Color.adaptive(light: "#FFFFFF", dark: "#1C1C1E")
    /// Karaoke follows the app appearance: paper-white in light mode, soft charcoal in dark.
    static let karaokePaper = Color.adaptive(light: "#FFFFFF", dark: "#1F1F1F")
    static let hairlineDark = Color.adaptive(light: "#E5E5EA", dark: "#2A2A2A")
    /// App page background — cream in light; night indigo (Sakura) or warm black (Amber) in dark.
    static var canvas: Color { JojoPalette.color(
        sakuraLight: "#FFF5F8", sakuraDark: "#0B0816",
        amberLight: "#FFF8F3", amberDark: "#100C08"
    ) }
    static let card = Color.adaptive(light: "#FFFFFF", dark: "#1C1C1E")
    /// Hairline on cards. Follows the theme paper, and the color scheme of the screen that draws it.
    static var cardStroke: Color {
        Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch JojoPalette.theme {
            case .sakura: return UIColor(hex: dark ? "#3A2448" : "#F3D0E0")
            case .amber: return UIColor(hex: dark ? "#3A2A16" : "#F3E4D4")
            }
        })
    }
    /// Quiet fills behind unselected chips and fields.
    static var fieldFill: Color {
        Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch JojoPalette.theme {
            case .sakura: return UIColor(hex: dark ? "#1C1428" : "#FFF0F5")
            case .amber: return UIColor(hex: dark ? "#1C140E" : "#FFF3E8")
            }
        })
    }
    /// Disabled primary fill. Dark enough for white type, still in the active theme.
    static var accentDisabled: Color {
        switch JojoPalette.theme {
        case .sakura: Color(hex: "#C45A80")
        case .amber: Color(hex: "#E08A4A")
        }
    }
    /// Active karaoke line card (Kiku-style raised surface).
    static let transcriptCard = Color.adaptive(light: "#FFFFFF", dark: "#2C2C2E")
    /// Soft lift behind the active karaoke line, in the active accent.
    static var activeLineGlow: Color { LearningInk.glow.opacity(0.55) }

    // MARK: Brand accent
    /// Marks, underlines, and icons. Each theme picks a shade that stays readable on its page.
    static var sakuraPink: Color { JojoPalette.color(
        sakuraLight: "#FF4D8D", sakuraDark: "#FF7EB8",
        amberLight: "#FF7A00", amberDark: "#FFB020"
    ) }
    static var sakuraPinkDeep: Color { sakuraPink }
    /// Soft chips. Pale on white, a solid dark tint at night so white type still reads.
    static var sakuraPinkLight: Color { JojoPalette.color(
        sakuraLight: "#FFE4EF", sakuraDark: "#6A2458",
        amberLight: "#FFE4CC", amberDark: "#6B3A12"
    ) }
    static var sakuraPinkSoft: Color { sakuraPinkLight }
    /// Fills that carry a white label.
    static var sakuraButton: Color { JojoPalette.color(
        sakuraLight: "#FF4D8D", sakuraDark: "#FF4D8D",
        amberLight: "#FF7A00", amberDark: "#FF7A00"
    ) }

    /// Accent fill on study screens. Follows Sakura or Amber.
    static var studyAccent: Color {
        switch JojoPalette.theme {
        case .sakura: Color(hex: "#FF4D8D")
        case .amber: Color(hex: "#FF7A00")
        }
    }

    /// Page wash behind Explore, Vocab, and Search. Cream in light, night paper in dark.
    static var studyPage: Color { JojoPalette.color(
        sakuraLight: "#FFF5F8", sakuraDark: "#0B0816",
        amberLight: "#FFF8F3", amberDark: "#100C08"
    ) }

    /// Today's-focus card and selected chips.
    static var studyFocus: Color { JojoPalette.color(
        sakuraLight: "#FFE4EF", sakuraDark: "#2A1838",
        amberLight: "#FFF1E4", amberDark: "#2A1C12"
    ) }

    static var studyMuted: Color { JojoPalette.color(
        sakuraLight: "#8A6574", sakuraDark: "#C7A8B8",
        amberLight: "#8A7364", amberDark: "#C8A88A"
    ) }

    /// Dock fill. Deep indigo for Sakura night, warm black for Amber night.
    static var dockFill: Color { JojoPalette.color(
        sakuraLight: "#1A1028", sakuraDark: "#140C2E",
        amberLight: "#1C140E", amberDark: "#100C08"
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

    /// Main-app chrome. Follows Sakura or Amber with the light or dark page.
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
        sakuraLight: "#FF4D8D", sakuraDark: "#FF7EB8",
        amberLight: "#FF7A00", amberDark: "#FFB020"
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
    static var spokenGreen: Color { LearningInk.spoken }
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
/// Feed hierarchy (Kiku-style): white Japanese, muted readings, POS underlines, green spoken cursor, accent tap.
enum LearningInk {
    /// Kanji and kana at rest. Near-black on white, white on night, for every accent.
    /// Portrait bands always use white ink so light-mode paper colors stay readable on footage.
    static var japanese: Color { japanese(onPicture: false) }
    static func japanese(onPicture: Bool) -> Color {
        if onPicture { return Color.white }
        return JojoPalette.color(
            sakuraLight: "#1A1020", sakuraDark: "#FFFFFF",
            amberLight: "#1C1208", amberDark: "#FFFFFF"
        )
    }
    /// Reading above a word. Quiet so underlines carry the grammar color.
    static var furigana: Color { furigana(onPicture: false) }
    static func furigana(onPicture: Bool) -> Color {
        if onPicture { return Color.white.opacity(0.78) }
        return JojoPalette.color(
            sakuraLight: "#6B5E66", sakuraDark: "#C7C7CC",
            amberLight: "#6B5E52", amberDark: "#C7C7CC"
        )
    }
    /// Romaji under a word. One step quieter than furigana.
    static var romaji: Color { romaji(onPicture: false) }
    static func romaji(onPicture: Bool) -> Color {
        if onPicture { return Color.white.opacity(0.62) }
        return JojoPalette.color(
            sakuraLight: "#8A7A82", sakuraDark: "#8E8E93",
            amberLight: "#8A7A6E", amberDark: "#8E8E93"
        )
    }
    /// Nouns, verbs, and adjectives — underline / POS only.
    static var content: Color { JojoPalette.color(
        sakuraLight: "#007EA8", sakuraDark: "#5CEBFF",
        amberLight: "#007EA8", amberDark: "#5CEBFF"
    ) }
    /// Particles and other function words — underline / POS only.
    static var particle: Color { JojoPalette.color(
        sakuraLight: "#E21888", sakuraDark: "#FF8A3D",
        amberLight: "#E21888", amberDark: "#FF8A3D"
    ) }
    /// Karaoke cursor: the word being spoken right now (lime green, like Kiku).
    static var spoken: Color { JojoPalette.color(
        sakuraLight: "#0B8A4C", sakuraDark: "#7CFF6B",
        amberLight: "#0B8A4C", amberDark: "#7CFF6B"
    ) }
    /// A word the learner marked known — fully green.
    static var known: Color { JojoPalette.color(
        sakuraLight: "#0B8A4C", sakuraDark: "#5DFFB0",
        amberLight: "#0E7A45", amberDark: "#5DFFB0"
    ) }
    /// Almost known — soft green, one step before Known.
    static var easy: Color { JojoPalette.color(
        sakuraLight: "#2FA86A", sakuraDark: "#8AFFB0",
        amberLight: "#2FA86A", amberDark: "#8AFFB0"
    ) }
    /// Still learning — amber wall (Yomi-style “new” heat).
    static var learning: Color { JojoPalette.color(
        sakuraLight: "#D97706", sakuraDark: "#FFB020",
        amberLight: "#C2410C", amberDark: "#FFB020"
    ) }
    /// Brand-new / never painted — warm amber so the line reads as a wall of work.
    static var unlearned: Color { JojoPalette.color(
        sakuraLight: "#B45309", sakuraDark: "#FF9F1A",
        amberLight: "#9A3412", amberDark: "#FF9F1A"
    ) }
    /// Tapped / selected word — accent rim, separate from the green spoken cursor.
    static var selected: Color { JojoPalette.color(
        sakuraLight: "#FF4D8D", sakuraDark: "#FF7EB8",
        amberLight: "#FF7A00", amberDark: "#FFB020"
    ) }
    /// Saved or familiar — accent ink between learning amber and easy green.
    static var familiar: Color { JojoPalette.color(
        sakuraLight: "#FF4D8D", sakuraDark: "#FF8AD4",
        amberLight: "#FF7A00", amberDark: "#FF8A3D"
    ) }

    /// Ink for a mastery mark on karaoke / ripen demos.
    static func mastery(_ state: SRSState?) -> Color {
        switch state {
        case .known: return known
        case .easy: return easy
        case .familiar: return familiar
        case .learning: return learning
        case .new, .none: return unlearned
        }
    }
    /// English under a karaoke line. Quiet white on night so Japanese stays primary.
    static var english: Color { english(onPicture: false) }
    static func english(onPicture: Bool) -> Color {
        if onPicture { return Color.white.opacity(0.88) }
        return JojoPalette.color(
            sakuraLight: "#3A2A32", sakuraDark: "#E5E5EA",
            amberLight: "#4A3828", amberDark: "#E5E5EA"
        )
    }
    /// Glow behind spoken / selected words only.
    static var glow: Color { JojoPalette.color(
        sakuraLight: "#FF4D8D", sakuraDark: "#FF4FA3",
        amberLight: "#FF7A00", amberDark: "#FFB020"
    ) }

    /// Dictionary plate. White in light mode, a night plate in dark mode, for every accent.
    static var dictionaryPlate: Color { JojoPalette.color(
        sakuraLight: "#FFFFFF", sakuraDark: "#140C18",
        amberLight: "#FFFFFF", amberDark: "#1A1008"
    ) }
    /// Headword on the dictionary card — same as karaoke Japanese so accent stays on the rim / selection.
    static var dictionaryWord: Color { japanese }
    /// Reading on the dictionary card — muted so the headword and gloss lead.
    static var dictionaryReading: Color { JojoPalette.color(
        sakuraLight: "#6B5E66", sakuraDark: "#C7C7CC",
        amberLight: "#6B5E52", amberDark: "#C7C7CC"
    ) }
    /// Primary gloss — readable white/ink, not a competing neon.
    static var dictionaryGloss: Color { JojoPalette.color(
        sakuraLight: "#1A1020", sakuraDark: "#F5F5F7",
        amberLight: "#1C1208", amberDark: "#F5F5F7"
    ) }
}

/// Colored halo behind a karaoke or dictionary word. Liquid adds a second, wider bloom.
struct TextGlowModifier: ViewModifier {
    var color: Color
    var level: GlowLevel
    var boosted: Bool = false

    func body(content: Content) -> some View {
        let scale = boosted ? 1.45 : 1
        let radius = level.radius * scale
        let alpha = level.intensity * (boosted ? 1 : 0.9)
        content
            .shadow(color: color.opacity(alpha), radius: radius)
            .shadow(color: color.opacity(level == .liquid ? alpha * 0.5 : 0), radius: radius * 2.1)
    }
}

extension View {
    func textGlow(_ color: Color, level: GlowLevel, boosted: Bool = false) -> some View {
        modifier(TextGlowModifier(color: color, level: level, boosted: boosted))
    }

    /// Accent rim glow for cards and the dock. Off removes it.
    func chromeGlow(_ color: Color, level: GlowLevel, radius: CGFloat = 12) -> some View {
        let alpha = level.intensity
        return self
            .shadow(color: color.opacity(alpha * 0.55), radius: radius * (level == .liquid ? 1.4 : 1))
            .shadow(color: color.opacity(level == .liquid ? alpha * 0.35 : 0), radius: radius * 2.2)
    }
}

/// Shared animation curves so feed, popup and tabs feel like one product.
enum Motion {
    static let lineAdvance = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let popupSpring = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let tabSlide = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let cardFlip = Animation.spring(response: 0.62, dampingFraction: 0.78)
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
    /// Kiku-style underline: blue for content words, amber for particles / auxiliaries / copula.
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

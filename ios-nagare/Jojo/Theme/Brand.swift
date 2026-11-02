import SwiftUI
import UIKit

// MARK: - Surfaces

/// Jojo renders on three surfaces. `cream` is the light-mode paper default.
/// `cinema` is reserved for screens where real video is playing. `night`
/// matches the iOS app icon: indigo / sakura sky, white type, sakura accents.
nonisolated enum BrandSurface: Sendable {
    case cream
    case cinema
    case night
}

/// Named night-sakura scene images used by onboarding backgrounds.
nonisolated enum BrandScene: String, Sendable, CaseIterable {
    case lanternNight = "SceneLanternNight"
    case neonTokyo = "SceneNeonTokyo"
    case templeDusk = "SceneTempleDusk"
    case sakuraDay = "SceneSakuraDay"
}

/// Mascot pose image names. Default keeps the existing book-holding asset.
nonisolated enum MascotPose: String, Sendable {
    case book = "JojoMascot"
    case peek = "JojoMascotPeek"
    case phone = "JojoMascotPhone"
    case wave = "JojoMascotWave"
    case cheer = "JojoMascotCheer"

    /// Falls back to the book pose when a generated asset is not yet in the catalog.
    var resolvedName: String {
        if UIImage(named: rawValue) != nil { return rawValue }
        return MascotPose.book.rawValue
    }
}

nonisolated struct BrandSurfaceKey: EnvironmentKey {
    static let defaultValue = BrandSurface.cream
}

extension EnvironmentValues {
    /// Surface the current subtree is painted on, so shared components can pick their own contrast.
    /// `nonisolated` because the project defaults to `@MainActor` and key paths can't be
    /// formed to actor-isolated properties.
    nonisolated var brandSurface: BrandSurface {
        get { self[BrandSurfaceKey.self] }
        set { self[BrandSurfaceKey.self] = newValue }
    }
}

/// Surface-resolved text colors. Components read these instead of hard-coding white or ink,
/// which is what lets one `OnboardingTitle` work on cream and over video.
struct BrandPalette {
    let title: Color
    let subtle: Color
    let faint: Color

    static func resolve(_ surface: BrandSurface) -> BrandPalette {
        switch surface {
        case .cream:
            BrandPalette(title: .jojoInk, subtle: .jojoInkSoft, faint: .jojoInkFaint)
        case .cinema:
            BrandPalette(
                title: .white,
                subtle: Color.white.opacity(0.6),
                faint: Color.white.opacity(0.38)
            )
        case .night:
            BrandPalette(
                title: .white,
                subtle: Color.white.opacity(0.82),
                faint: Color.white.opacity(0.62)
            )
        }
    }
}

// MARK: - Backgrounds

/// The onboarding canvas. Pass a `scene` for the night-sakura App Store look; omit it
/// for the classic cream paper with seigaiha hills.
struct JojoBrandBackground: View {
    /// When set, paints a night scene with scrim + lantern glow instead of cream paper.
    var scene: BrandScene? = nil
    var showsHills: Bool = true
    var showsPetals: Bool = true

    @State private var kenBurns: Bool = false

    var body: some View {
        ZStack {
            if let scene {
                nightScene(scene)
            } else {
                creamScene
            }
            if showsPetals {
                BrandPetalField(
                    tint: .sakuraPinkSoft,
                    density: scene == nil ? .sparse : .lush
                )
            }
            if showsHills, scene == nil {
                VStack {
                    Spacer()
                    SeigaihaHills()
                        .frame(height: 120)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var creamScene: some View {
        ZStack {
            LinearGradient(
                colors: [.jojoCream, .jojoCreamDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.sakuraPinkSoft, .clear],
                center: .init(x: 0.88, y: 0.04),
                startRadius: 8,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.sakuraPinkSoft, .clear],
                center: .init(x: 0.02, y: 0.34),
                startRadius: 8,
                endRadius: 320
            )
        }
    }

    private func nightScene(_ scene: BrandScene) -> some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [.nightIndigo, .nightViolet, .nightPlum],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if UIImage(named: scene.rawValue) != nil {
                    Image(scene.rawValue)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(kenBurns ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: kenBurns)
                        .clipped()
                }
                // Stronger scrim so night-onboarding copy stays readable over the icon sky.
                LinearGradient(
                    colors: [
                        Color.nightIndigo.opacity(0.72),
                        Color.nightIndigo.opacity(0.42),
                        Color.nightIndigo.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color.sakuraPinkSoft, .clear],
                    center: .init(x: 0.82, y: 0.18),
                    startRadius: 10,
                    endRadius: 380
                )
                RadialGradient(
                    colors: [Color.nightViolet.opacity(0.18), .clear],
                    center: .init(x: 0.12, y: 0.78),
                    startRadius: 8,
                    endRadius: 280
                )
            }
            .onAppear {
                kenBurns = true
            }
        }
    }
}

/// Near-black atmospheric background with a slow warm glow. Video screens only.
struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color.bgPlayer
            RadialGradient(colors: [Color.sakuraPinkSoft, .clear], center: .init(x: 0.85, y: -0.05), startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(hex: "#3B82F6").opacity(0.08), .clear], center: .init(x: 0.0, y: 1.0), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Seigaiha hills

/// Layered sakura hills with a quiet seigaiha (wave) pattern — brand footer.
struct SeigaihaHills: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            SeigaihaHillShape(phase: 0)
                .fill(Color.sakuraPinkSoft)
                .frame(height: 104)
            SeigaihaHillShape(phase: 18)
                .fill(Color.sakuraPink)
                .frame(height: 80)
            SeigaihaPattern()
                .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                .frame(height: 80)
                .mask(SeigaihaHillShape(phase: 18))
        }
        .frame(maxWidth: .infinity)
    }
}

struct SeigaihaHillShape: Shape {
    var phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wave = rect.height * 0.22
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: wave + phase * 0.4))
        path.addCurve(
            to: CGPoint(x: rect.width, y: wave * 0.7 + phase * 0.2),
            control1: CGPoint(x: rect.width * 0.28, y: -wave * 0.2 + phase),
            control2: CGPoint(x: rect.width * 0.62, y: wave * 1.6)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct SeigaihaPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 28
        var y: CGFloat = rect.height * 0.15
        var row = 0
        while y < rect.height + spacing {
            let xOffset: CGFloat = row.isMultiple(of: 2) ? 0 : spacing * 0.5
            var x = -spacing + xOffset
            while x < rect.width + spacing {
                for scale: CGFloat in [1, 0.7, 0.4] {
                    let r = 16 * scale
                    path.addArc(
                        center: CGPoint(x: x, y: y),
                        radius: r,
                        startAngle: .degrees(200),
                        endAngle: .degrees(340),
                        clockwise: false
                    )
                }
                x += spacing
            }
            y += spacing * 0.55
            row += 1
        }
        return path
    }
}

// MARK: - Blossom

/// Five-petal sakura, matching the blossoms in the app icon.
struct Blossom: View {
    var size: CGFloat = 18
    var color: Color = .jojoBlossom

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Ellipse()
                    .fill(color)
                    .frame(width: size * 0.42, height: size * 0.62)
                    .offset(y: -size * 0.2)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
            Circle()
                .fill(color.opacity(0.55))
                .frame(width: size * 0.2, height: size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

nonisolated enum PetalDensity: Sendable {
    case sparse, lush
}

/// Petals drifting down the canvas. Sparse on cream; lush (larger, pinker) on night scenes.
struct BrandPetalField: View {
    var tint: Color = .jojoBlossom
    var density: PetalDensity = .sparse

    private struct Petal: Identifiable {
        let id: Int
        let x: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
        let spin: Double
    }

    @State private var fall: Bool = false

    private var petals: [Petal] {
        switch density {
        case .sparse:
            [
                Petal(id: 0, x: 0.08, size: 15, duration: 17, delay: 0, spin: 140),
                Petal(id: 1, x: 0.24, size: 10, duration: 22, delay: 3.5, spin: -110),
                Petal(id: 2, x: 0.47, size: 13, duration: 19, delay: 7, spin: 170),
                Petal(id: 3, x: 0.68, size: 9, duration: 25, delay: 1.5, spin: -150),
                Petal(id: 4, x: 0.86, size: 14, duration: 20, delay: 9, spin: 120),
                Petal(id: 5, x: 0.95, size: 8, duration: 27, delay: 5, spin: -90)
            ]
        case .lush:
            [
                Petal(id: 0, x: 0.05, size: 18, duration: 14, delay: 0, spin: 160),
                Petal(id: 1, x: 0.16, size: 12, duration: 18, delay: 1.2, spin: -130),
                Petal(id: 2, x: 0.28, size: 16, duration: 15, delay: 3.0, spin: 190),
                Petal(id: 3, x: 0.42, size: 11, duration: 20, delay: 0.6, spin: -100),
                Petal(id: 4, x: 0.55, size: 19, duration: 13, delay: 4.5, spin: 140),
                Petal(id: 5, x: 0.68, size: 13, duration: 17, delay: 2.1, spin: -170),
                Petal(id: 6, x: 0.80, size: 15, duration: 16, delay: 5.5, spin: 110),
                Petal(id: 7, x: 0.92, size: 10, duration: 21, delay: 1.8, spin: -145),
                Petal(id: 8, x: 0.35, size: 9, duration: 23, delay: 7.0, spin: 95),
                Petal(id: 9, x: 0.74, size: 17, duration: 14.5, delay: 8.2, spin: -155)
            ]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(petals) { petal in
                    Blossom(size: petal.size, color: tint.opacity(density == .lush ? 0.7 : 0.5))
                        .rotationEffect(.degrees(fall ? petal.spin : 0))
                        .offset(
                            x: proxy.size.width * petal.x + (fall ? 32 : -24),
                            y: fall ? proxy.size.height + 40 : -40
                        )
                        .animation(
                            .linear(duration: petal.duration)
                            .repeatForever(autoreverses: false)
                            .delay(petal.delay),
                            value: fall
                        )
                }
            }
        }
        .onAppear { fall = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Mascot & wordmark

/// Jojo the panda, cut out so it can sit on cream, on orange or inside a card.
struct JojoMascot: View {
    var height: CGFloat = 220
    /// Slow breathing bob. Off for static illustrations.
    var floats: Bool = true
    var pose: MascotPose = .book

    @State private var up: Bool = false

    var body: some View {
        Image(pose.resolvedName)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .offset(y: up ? -6 : 6)
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: up)
            .onAppear { if floats { up = true } }
            .accessibilityLabel("Jojo the panda")
    }
}

/// Static, centered mascot for navigation and compact brand headers.
struct JojoBrandIcon: View {
    var size: CGFloat = 40

    var body: some View {
        Image(MascotPose.book.rawValue)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Jojo")
    }
}

/// Head-and-shoulders crop in a cream disc — the recurring guide avatar.
struct JojoMascotAvatar: View {
    var size: CGFloat = 56
    var showsRing: Bool = true

    var body: some View {
        Image("JojoMascotHead")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Color.jojoCream)
            .clipShape(Circle())
            .overlay {
                if showsRing {
                    Circle().strokeBorder(Color.sakuraPink, lineWidth: max(2, size * 0.05))
                }
            }
            .accessibilityLabel("Jojo")
    }
}

/// The "Jojo" wordmark: heavy rounded type with the sakura ramp and a hinomaru-pink dot.
struct JojoWordmark: View {
    var size: CGFloat = 42

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.05) {
            Text("Jojo")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.sakuraPink)
            Circle()
                .fill(Color.sakuraPinkDeep)
                .frame(width: size * 0.19, height: size * 0.19)
                .offset(y: size * 0.14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jojo")
    }
}

// MARK: - Coach

/// Jojo speaking to the learner. Used at the top of question steps so the mascot
/// carries the funnel instead of a bare headline.
struct MascotCoach: View {
    let message: String
    var avatarSize: CGFloat = 52

    @Environment(\.brandSurface) private var surface

    private var isNight: Bool { surface == .night || surface == .cinema }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            JojoMascotAvatar(size: avatarSize)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isNight ? Color.white : Color.jojoInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s + 2)
                .background {
                    SpeechBubble()
                        .fill(isNight ? Color.white.opacity(0.12) : Color.jojoPaper)
                        .shadow(color: Color.black.opacity(isNight ? 0 : 0.06), radius: 8, y: 3)
                }
                .overlay {
                    SpeechBubble().stroke(isNight ? Color.white.opacity(0.14) : Color.jojoPaperStroke, lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jojo says: \(message)")
    }
}

/// Rounded rectangle with a small tail pointing left toward the avatar.
struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tail: CGFloat = 8
        let bubble = CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        var path = Path(roundedRect: bubble, cornerRadius: radius, style: .continuous)
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: bubble.minX + 1, y: midY - 9))
        path.addLine(to: CGPoint(x: bubble.minX + 1, y: midY + 9))
        path.closeSubpath()
        return path
    }
}

// MARK: - Card chrome

extension View {
    /// White paper card with the brand hairline and a warm shadow.
    func brandCard(radius: CGFloat = Radius.sheet, padding: CGFloat? = Spacing.l) -> some View {
        self
            .padding(padding ?? 0)
            .background(Color.jojoPaper, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.jojoPaperStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }
}

/// Quiet secondary action on the cream surface (paired with `PrimaryButtonStyle`).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.jojoInk)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.jojoPaper, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Color.jojoPaperStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

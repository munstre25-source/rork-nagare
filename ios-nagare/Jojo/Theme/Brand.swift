import SwiftUI

// MARK: - Surfaces

/// Jojo renders on two surfaces. `cream` is the brand default — the same warm paper the
/// app icon sits on. `cinema` is reserved for screens where real video is playing, where
/// anything but near-black would fight the footage.
nonisolated enum BrandSurface: Sendable {
    case cream
    case cinema
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
        }
    }
}

// MARK: - Backgrounds

/// The onboarding canvas: warm cream paper, a low sun glow, drifting blossom and
/// seigaiha hills along the bottom. Every question screen sits on this so the
/// branding never resets between steps.
struct JojoBrandBackground: View {
    var showsHills: Bool = true
    var showsPetals: Bool = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.jojoCream, .jojoCreamDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.jojoOrange.opacity(0.16), .clear],
                center: .init(x: 0.88, y: 0.04),
                startRadius: 8,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.jojoBlossom.opacity(0.18), .clear],
                center: .init(x: 0.02, y: 0.34),
                startRadius: 8,
                endRadius: 320
            )
            if showsPetals {
                BrandPetalField()
            }
            if showsHills {
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
}

/// Near-black atmospheric background with a slow warm glow. Video screens only.
struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            Color.bgPlayer
            RadialGradient(colors: [Color.jojoOrange.opacity(0.22), .clear], center: .init(x: 0.85, y: -0.05), startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(hex: "#3B82F6").opacity(0.08), .clear], center: .init(x: 0.0, y: 1.0), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Seigaiha hills

/// Layered orange hills with a quiet seigaiha (wave) pattern — brand footer, not decoration noise.
struct SeigaihaHills: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            SeigaihaHillShape(phase: 0)
                .fill(Color.jojoOrangeLight.opacity(0.5))
                .frame(height: 104)
            SeigaihaHillShape(phase: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.jojoOrange.opacity(0.92), Color.jojoVermilion.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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

/// Petals drifting down the cream canvas. Deliberately sparse and slow — ambient, not confetti.
struct BrandPetalField: View {
    private struct Petal {
        let x: CGFloat
        let size: CGFloat
        let duration: Double
        let delay: Double
        let spin: Double
    }

    @State private var fall: Bool = false

    private let petals: [Petal] = [
        Petal(x: 0.08, size: 15, duration: 17, delay: 0, spin: 140),
        Petal(x: 0.24, size: 10, duration: 22, delay: 3.5, spin: -110),
        Petal(x: 0.47, size: 13, duration: 19, delay: 7, spin: 170),
        Petal(x: 0.68, size: 9, duration: 25, delay: 1.5, spin: -150),
        Petal(x: 0.86, size: 14, duration: 20, delay: 9, spin: 120),
        Petal(x: 0.95, size: 8, duration: 27, delay: 5, spin: -90)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(Array(petals.enumerated()), id: \.offset) { _, petal in
                    Blossom(size: petal.size, color: Color.jojoBlossom.opacity(0.5))
                        .rotationEffect(.degrees(fall ? petal.spin : 0))
                        .offset(
                            x: proxy.size.width * petal.x + (fall ? 26 : -26),
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

    @State private var up: Bool = false

    var body: some View {
        Image("JojoMascot")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .offset(y: up ? -6 : 6)
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: up)
            .onAppear { if floats { up = true } }
            .accessibilityLabel("Jojo the panda")
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
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.jojoOrangeLight, Color.jojoVermilion],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(2, size * 0.05)
                    )
                }
            }
            .accessibilityLabel("Jojo")
    }
}

/// The "Jojo" wordmark: heavy rounded type with the orange ramp and a hinomaru dot.
struct JojoWordmark: View {
    var size: CGFloat = 42

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.05) {
            Text("Jojo")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.jojoOrangeLight, Color.jojoOrange, Color.jojoVermilion],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(Color.jojoVermilion)
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

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            JojoMascotAvatar(size: avatarSize)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.jojoInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s + 2)
                .background {
                    SpeechBubble()
                        .fill(Color.jojoPaper)
                        .shadow(color: Color.jojoVermilion.opacity(0.08), radius: 10, y: 4)
                }
                .overlay {
                    SpeechBubble().stroke(Color.jojoPaperStroke, lineWidth: 1)
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
            .shadow(color: Color.jojoVermilion.opacity(0.07), radius: 14, y: 6)
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

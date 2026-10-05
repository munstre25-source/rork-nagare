import SwiftUI

/// Live preview of the six looks and four text glows, right before the paywall.
struct LookStepView: View {
    let onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @State private var breath = false

    private var paint: LookPaint { LookPaint.matching(app.profile.theme, app.profile.scheme) }

    private var continueTitle: String {
        let name = app.profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "This is my Jojo" : "This is \(name)'s Jojo"
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    OnboardingTitle(
                        title: "Make it yours",
                        subtitle: "Six looks. Four glows. This is the Jojo you'll open instead of another scroll.",
                        accent: "yours"
                    )
                    LookStage(paint: paint, glow: app.profile.glow, breath: breath)
                    lookPicker
                    glowPicker
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.m)
                .padding(.bottom, Spacing.s)
            }
            .scrollIndicators(.hidden)

            settingsNote
            Button(continueTitle) { finish() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.l)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                breath = true
            }
        }
    }

    private var lookPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Pick a look")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            LazyVGrid(columns: LookStepMetrics.columns, spacing: 10) {
                ForEach(LookPaint.all) { paint in
                    LookSwatch(paint: paint, selected: paint.id == self.paint.id) {
                        choose(paint)
                    }
                }
            }
        }
    }

    private var glowPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("How the words glow")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            LookGlowRow(glow: app.profile.glow) { level in
                guard app.profile.glow != level else { return }
                Haptics.selection()
                app.setGlowLevel(level)
            }
            Text(glowLine)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsNote: some View {
        Text("You can change the look and the glow anytime in Profile settings.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.l)
    }

    private var glowLine: String {
        switch app.profile.glow {
        case .off: "Clean. Just the word."
        case .soft: "A quiet halo on every word you tap."
        case .glow: "The word lights up in the sentence."
        case .liquid: "It breathes. This is the one people keep."
        }
    }

    private func choose(_ paint: LookPaint) {
        let themeChanged = app.profile.theme != paint.theme
        let schemeChanged = app.profile.scheme != paint.scheme
        guard themeChanged || schemeChanged else { return }
        Haptics.selection()
        if themeChanged { app.setTheme(paint.theme) }
        if schemeChanged { app.setScheme(paint.scheme) }
    }

    private func finish() {
        Haptics.medium()
        track("onboarding_look_chosen", props: [
            "theme": app.profile.theme.rawValue,
            "scheme": app.profile.scheme.rawValue,
            "glow": app.profile.glow.rawValue
        ])
        onContinue()
    }
}

private enum LookStepMetrics {
    static let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
}

/// One of the six paints: Sakura, Lavender, and Orange, each in light and dark.
private struct LookPaint: Identifiable, Hashable {
    let theme: AccentTheme
    let scheme: JojoScheme
    let paper: Color
    let accent: Color
    let ink: Color
    let muted: Color
    let chip: Color

    var id: String { "\(theme.rawValue)-\(scheme.rawValue)" }

    static func matching(_ theme: AccentTheme, _ scheme: JojoScheme) -> LookPaint {
        all.first { $0.theme == theme && $0.scheme == scheme } ?? all[0]
    }

    static let all: [LookPaint] = [
        LookPaint(theme: .sakura, scheme: .light, paper: Color(hex: "#FFF5F8"), accent: Color(hex: "#FF4D8D"), ink: Color(hex: "#2A1A22"), muted: Color(hex: "#8A6574"), chip: Color(hex: "#FFE4EF")),
        LookPaint(theme: .plum, scheme: .light, paper: Color(hex: "#F6F1FF"), accent: Color(hex: "#8B5CF6"), ink: Color(hex: "#241A33"), muted: Color(hex: "#7A6A8A"), chip: Color(hex: "#EDE4FF")),
        LookPaint(theme: .orange, scheme: .light, paper: Color(hex: "#FFF8F3"), accent: Color(hex: "#FF7A00"), ink: Color(hex: "#2A1C12"), muted: Color(hex: "#8A7364"), chip: Color(hex: "#FFE4CC")),
        LookPaint(theme: .sakura, scheme: .dark, paper: Color(hex: "#0B0816"), accent: Color(hex: "#FF7EB8"), ink: Color.white, muted: Color(hex: "#E7C3D6"), chip: Color(hex: "#6A2458")),
        LookPaint(theme: .plum, scheme: .dark, paper: Color(hex: "#0B0816"), accent: Color(hex: "#C4B5FD"), ink: Color.white, muted: Color(hex: "#D4C8EE"), chip: Color(hex: "#4C3A72")),
        LookPaint(theme: .orange, scheme: .dark, paper: Color(hex: "#0B0816"), accent: Color(hex: "#FFB020"), ink: Color.white, muted: Color(hex: "#F0D7B0"), chip: Color(hex: "#6B3A12"))
    ]
}

private struct LookStage: View {
    let paint: LookPaint
    let glow: GlowLevel
    let breath: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("For You")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(paint.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(paint.chip, in: Capsule())
                Spacer(minLength: 8)
                Text("\(paint.theme.title) · \(paint.scheme.title)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paint.muted)
            }
            Text("すき")
                .font(.caption.weight(.semibold))
                .foregroundStyle(paint.muted)
                .frame(maxWidth: .infinity)
            Text("好き")
                .font(JojoFont.jp(64, bold: true, relativeTo: .largeTitle))
                .foregroundStyle(paint.accent)
                .textGlow(paint.accent, level: glow, boosted: breath && glow != .off)
                .frame(maxWidth: .infinity)
            Text("I like this.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(paint.ink)
                .frame(maxWidth: .infinity)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .background(paint.paper, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(paint.accent.opacity(0.45), lineWidth: 1.5)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: paint.id)
        .animation(.easeInOut(duration: 0.35), value: glow)
    }
}

private struct LookSwatch: View {
    let paint: LookPaint
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("光")
                    .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                    .foregroundStyle(paint.accent)
                    .textGlow(paint.accent, level: selected ? .glow : .soft)
                Text(paint.theme.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(paint.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(paint.scheme.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(paint.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(paint.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? paint.accent : Color.white.opacity(0.18), lineWidth: selected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(paint.theme.title) \(paint.scheme.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LookGlowRow: View {
    let glow: GlowLevel
    let onSelect: (GlowLevel) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GlowLevel.allCases) { level in
                LookGlowPill(level: level, selected: glow == level) {
                    onSelect(level)
                }
            }
        }
    }
}

private struct LookGlowPill: View {
    let level: GlowLevel
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(level.title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(.white)
                .background {
                    Capsule().fill(selected ? AnyShapeStyle(Color.sakuraButton) : AnyShapeStyle(Color.white.opacity(0.14)))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(level.title) glow")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

import SwiftUI
import StoreKit

/// Dedicated App Store review ask after the aha moment, before the paywall.
/// Soft cream surface so Jojo feels intimate and branded — not another dark question card.
struct AppReviewStepView: View {
    let onContinue: () -> Void

    @Environment(\.requestReview) private var requestReview
    @State private var appeared = false
    @State private var starsLit = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Parent already paints cream; keep soft glow + hills here.
            RadialGradient(
                colors: [Color.nagareOrange.opacity(0.12), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .frame(height: 420)
            .offset(y: -40)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Spacing.l) {
                        wordmark
                            .padding(.top, Spacing.m)

                        VStack(spacing: Spacing.s) {
                            Text("How is Jojo doing?")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: "#2A2A2A"))
                                .multilineTextAlignment(.center)
                            Text("Help us grow with a quick rating.\nJojo loves your feedback!")
                                .font(.body)
                                .foregroundStyle(Color(hex: "#6B6B6B"))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, Spacing.l)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)

                        ratingRow
                            .padding(.top, Spacing.s)
                            .opacity(appeared ? 1 : 0)

                        Image("JojoReviewHero")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 320)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Spacing.l)
                            .scaleEffect(appeared ? 1 : 0.94)
                            .opacity(appeared ? 1 : 0)
                            .accessibilityLabel("Jojo the panda, learning Japanese with you")
                    }
                    .padding(.bottom, 180)
                }

                VStack(spacing: Spacing.m) {
                    Button {
                        Haptics.medium()
                        track("onboarding_appreview_rated")
                        Task { @MainActor in
                            requestReview()
                            // Give the system sheet a beat before advancing to paywall.
                            try? await Task.sleep(for: .milliseconds(500))
                            onContinue()
                        }
                    } label: {
                        Text("I rated Jojo")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        Haptics.selection()
                        track("onboarding_appreview_skipped")
                        onContinue()
                    } label: {
                        Text("Not now")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(hex: "#8A8A8A"))
                            .underline()
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.l)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#FFF6EE").opacity(0), Color(hex: "#FFF6EE")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false),
                    alignment: .top
                )
            }

            SeigaihaHills()
                .frame(height: 110)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { appeared = true }
            animateStars()
        }
    }

    private var wordmark: some View {
        HStack(alignment: .top, spacing: 2) {
            Text("Jojo")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#FF8A2B"), Color.nagareOrange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(Color.nagareOrange)
                .frame(width: 8, height: 8)
                .offset(x: -2, y: 6)
                .opacity(0.9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jojo")
    }

    private var ratingRow: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: "#E8B84A"))
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: "star.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(index < starsLit ? Color(hex: "#F5C542") : Color(hex: "#E5E0D8"))
                        .scaleEffect(index < starsLit ? 1 : 0.86)
                        .animation(.spring(response: 0.35, dampingFraction: 0.65).delay(Double(index) * 0.05), value: starsLit)
                }
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(hex: "#E8B84A"))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Five star rating")
    }

    private func animateStars() {
        Task { @MainActor in
            for i in 1...5 {
                try? await Task.sleep(for: .milliseconds(90))
                starsLit = i
                Haptics.selection()
            }
        }
    }
}

/// Layered orange hills with a quiet seigaiha (wave) pattern — brand footer, not decoration noise.
private struct SeigaihaHills: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            SeigaihaHillShape(phase: 0)
                .fill(Color(hex: "#FFB25A").opacity(0.55))
                .frame(height: 100)
            SeigaihaHillShape(phase: 18)
                .fill(Color.nagareOrange.opacity(0.85))
                .frame(height: 78)
            SeigaihaPattern()
                .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                .frame(height: 78)
                .mask(SeigaihaHillShape(phase: 18))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SeigaihaHillShape: Shape {
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

private struct SeigaihaPattern: Shape {
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

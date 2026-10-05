import SwiftUI

/// Due count and streak, once on the first open of the day.
struct WelcomeHomeBurst: View {
    var due: Int
    var streak: Int
    @State private var shown = false
    @State private var dueShown = 0
    @State private var streakShown = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("Welcome back")
                .font(.headline.weight(.bold))
            if streak > 0 {
                Text("\(streakShown)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.designOrange)
                    .contentTransition(.numericText(value: Double(streakShown)))
                Text("streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if due > 0 {
                Text("\(dueShown) due")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.sakuraButton)
                    .contentTransition(.numericText(value: Double(dueShown)))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.sakuraButton.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: Color.sakuraButton.opacity(shown ? 0.35 : 0), radius: 24)
        .scaleEffect(shown ? 1 : 0.55)
        .opacity(shown ? 1 : 0)
        .onAppear {
            Haptics.heavy()
            withAnimation(.spring(response: 0.48, dampingFraction: 0.62)) {
                shown = true
                dueShown = due
                streakShown = streak
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The saved word pops, then flies down into the Vocab tab.
struct WordFlightView: View {
    var surface: String
    var reading: String
    @State private var flown = false
    @State private var popped = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                if !reading.isEmpty {
                    Text(reading)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.sakuraButton)
                        .lineLimit(1)
                }
                Text(surface)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.sakuraButton.opacity(0.4), radius: popped && !flown ? 16 : 0)
            .scaleEffect(flown ? 0.28 : (popped ? 1.08 : 0.4))
            .position(
                x: geo.size.width / 2,
                y: flown ? geo.size.height - 28 : geo.size.height * 0.42
            )
            .opacity(flown ? 0 : 1)
        }
        .allowsHitTesting(false)
        .onAppear {
            Haptics.medium()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) { popped = true }
            Task {
                try? await Task.sleep(for: .milliseconds(460))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { flown = true }
            }
        }
    }
}

/// The Vocab count springs when a new card lands. The capsule layout stays put.
struct BadgePop: ViewModifier {
    var value: Int
    @State private var popped = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(popped ? 1.4 : 1)
            .onChange(of: value) { _, _ in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { popped = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { popped = false }
                }
            }
    }
}

/// Chunky press for the review button. The tab capsule is unchanged.
struct ChunkyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

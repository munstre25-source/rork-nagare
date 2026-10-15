import SwiftUI

struct BornCardPayload: Equatable {
    var surface: String
    var romaji: String
    var gloss: String
}

/// The card that springs into existence the moment a word is tapped for the first time, then flies into Vocab.
struct BornFlashcard: View {
    let surface: String
    let romaji: String
    let gloss: String
    var onFinished: () -> Void

    @Environment(AppModel.self) private var app
    @State private var appeared = false
    @State private var flipped = false
    @State private var flying = false

    var body: some View {
        let glow = app.profile.glow
        return ZStack {
            if !flipped {
                face(title: "New card", detail: nil, glow: glow)
            }
            if flipped {
                face(title: gloss.isEmpty ? "Card saved" : gloss, detail: romaji, glow: glow)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .padding(18)
        .frame(maxWidth: 260, minHeight: 150)
        .background(FlashcardInk.plate, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.sakuraPink.opacity(glow == .off ? 0.35 : 0.9), lineWidth: 1.5)
        )
        .shadow(color: Color.sakuraPink.opacity(0.45 * glow.intensity), radius: glow == .off ? 0 : 16, y: glow == .off ? 0 : 6)
        .chromeGlow(Color.sakuraPink, level: glow, radius: 12)
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(flying ? 0.15 : (appeared ? 1 : 0.4))
        .offset(y: flying ? 280 : (appeared ? 0 : 40))
        .opacity(flying ? 0 : (appeared ? 1 : 0))
        .allowsHitTesting(false)
        .onAppear {
            Haptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { appeared = true }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.35)) { flipped = true }
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                withAnimation(.easeIn(duration: 0.45)) { flying = true }
                try? await Task.sleep(for: .milliseconds(480))
                onFinished()
            }
        }
    }

    private func face(title: String, detail: String?, glow: GlowLevel) -> some View {
        VStack(spacing: 8) {
            Text(surface)
                .font(JojoFont.jp(34, bold: true, relativeTo: .largeTitle))
                .foregroundStyle(FlashcardInk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textGlow(Color.sakuraPink, level: glow)
            if let detail, !detail.isEmpty {
                Text(detail.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(FlashcardInk.ink.opacity(0.9))
                    .lineLimit(1)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(detail == nil ? FlashcardInk.muted : Color.sakuraPink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

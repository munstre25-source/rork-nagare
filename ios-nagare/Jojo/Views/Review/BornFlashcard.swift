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

    @State private var appeared = false
    @State private var flipped = false
    @State private var flying = false

    var body: some View {
        ZStack {
            if !flipped {
                face(title: "New card", detail: nil)
            }
            if flipped {
                face(title: gloss.isEmpty ? "Card saved" : gloss, detail: romaji)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .padding(18)
        .frame(maxWidth: 240, minHeight: 140)
        .background(Color(hex: "#1C1C1E"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
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

    private func face(title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Text(surface)
                .font(JojoFont.jp(34, bold: true, relativeTo: .largeTitle))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(detail == nil ? .white.opacity(0.7) : Color.designOrange)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

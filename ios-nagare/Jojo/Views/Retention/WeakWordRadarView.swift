import SwiftUI

/// Surfaces POS / JLPT gaps and opens a mini review for that pocket.
struct WeakWordRadarView: View {
    let pockets: [WeakWordPocket]
    var onReview: (WeakWordPocket) -> Void

    var body: some View {
        if !pockets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weak-word radar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("Gaps in what you meet most")
                    .font(.headline.weight(.bold))
                ForEach(pockets) { pocket in
                    Button {
                        onReview(pocket)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pocket.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(pocket.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Text("\(pocket.keys.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 28)
                                .background(Color.sakuraButton, in: Capsule())
                        }
                        .padding(12)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.cardStroke)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

nonisolated struct WeakWordPocket: Identifiable, Hashable, Sendable {
    var id: String { title + subtitle }
    var title: String
    var subtitle: String
    var keys: [String]
}

import SwiftUI

/// Compact Joyo-kanji collection grid filled from Known / Easy vocabulary.
struct KanjiWallCard: View {
    let progress: KanjiWallProgress
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.selection()
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kanji wall")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(progress.count) of \(progress.total) · \(progress.percent)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kanji wall, \(progress.count) of \(progress.total) collected")
            .accessibilityHint(expanded ? "Collapse" : "Expand the collection grid")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.studyAccent.opacity(0.85))
                        .frame(width: max(4, proxy.size.width * CGFloat(progress.percent) / 100))
                }
            }
            .frame(height: 4)

            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(Array(KanjiWallProgress.joyoSeed.enumerated()), id: \.offset) { _, kanji in
                        Text(String(kanji))
                            .font(JojoFont.jp(16, bold: true, relativeTo: .callout))
                            .foregroundStyle(progress.collected.contains(kanji) ? LearningInk.japanese : Color.secondary.opacity(0.35))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(progress.collected.contains(kanji)
                                          ? Color.studyAccent.opacity(0.12)
                                          : Color.clear)
                            )
                            .accessibilityLabel(
                                progress.collected.contains(kanji)
                                    ? "\(kanji), collected"
                                    : "\(kanji), not yet"
                            )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .cardStyle()
    }
}

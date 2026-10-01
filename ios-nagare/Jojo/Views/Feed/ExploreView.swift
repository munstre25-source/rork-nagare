import SwiftUI

/// Browsable clip library with Difficulty / Topic / Source filters. Cards show a paused poster
/// with two play buttons: full clip, and loop the first line.
struct ExploreView: View {
    let onPlay: (Clip, Int?) -> Void

    @Environment(AppModel.self) private var app
    @State private var difficulty: Difficulty?
    @State private var topic: ClipCategory?
    @State private var source: SourceType?
    @State private var favoritesOnly: Bool = false

    private var filtered: [Clip] {
        app.clips.filter { clip in
            (difficulty == nil || clip.difficultyKind == difficulty)
                && (topic == nil || clip.categoryKind == topic)
                && (source == nil || clip.categoryKind.sourceType == source)
                && (!favoritesOnly || app.isFavorite(clip.id))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                filters
                if filtered.isEmpty {
                    VStack(spacing: Spacing.m) {
                        Image(systemName: favoritesOnly ? "bookmark" : "line.3.horizontal.decrease.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.4))
                        Text(favoritesOnly ? "Long-press any clip or tap the bookmark to save it here." : "No clips match these filters yet.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Button("Clear filters") { clearFilters() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.jojoOrange)
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Spacing.l)], spacing: Spacing.l) {
                        ForEach(filtered) { clip in
                            ExploreClipCard(clip: clip, onPlay: onPlay)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                }
            }
            .padding(.vertical, Spacing.m)
        }
        .scrollIndicators(.hidden)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                Button {
                    Haptics.selection()
                    favoritesOnly.toggle()
                } label: {
                    FilterChip(title: "Saved", systemImage: favoritesOnly ? "bookmark.fill" : "bookmark", isSelected: favoritesOnly, dark: true)
                }
                Menu {
                    Button("Any difficulty") { difficulty = nil }
                    ForEach(Difficulty.allCases) { d in
                        Button(d.rawValue) { difficulty = d }
                    }
                } label: {
                    FilterChip(title: difficulty?.rawValue ?? "Difficulty", systemImage: "chart.bar.fill", isSelected: difficulty != nil, dark: true)
                }
                Menu {
                    Button("Any topic") { topic = nil }
                    ForEach(ClipCategory.allCases) { c in
                        Button { topic = c } label: { Label(c.displayName, systemImage: c.symbol) }
                    }
                } label: {
                    FilterChip(title: topic?.displayName ?? "Topic", systemImage: "square.grid.2x2.fill", isSelected: topic != nil, dark: true)
                }
                Menu {
                    Button("Any source") { source = nil }
                    ForEach(SourceType.allCases) { s in
                        Button(s.displayName) { source = s }
                    }
                } label: {
                    FilterChip(title: source?.displayName ?? "Source type", systemImage: "play.tv.fill", isSelected: source != nil, dark: true)
                }
                if difficulty != nil || topic != nil || source != nil || favoritesOnly {
                    Button("Clear") { clearFilters() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.jojoOrange)
                        .frame(minHeight: 44)
                }
            }
        }
        .contentMargins(.horizontal, Spacing.l, for: .scrollContent)
    }

    private func clearFilters() {
        withAnimation(.snappy) {
            difficulty = nil
            topic = nil
            source = nil
            favoritesOnly = false
        }
    }
}

private struct ExploreClipCard: View {
    let clip: Clip
    let onPlay: (Clip, Int?) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Color.bgElevatedDark
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { GradientPoster(clip: clip).allowsHitTesting(false) }
                .overlay(alignment: .bottomLeading) {
                    if let line = clip.lines.first {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .font(JojoFont.jp(17, bold: true, relativeTo: .headline))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(line.translation)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .padding(Spacing.m)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Text(formatClock(clip.durationSec))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(Spacing.s)
                }
                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
            HStack(spacing: Spacing.m) {
                ChannelAvatar(clip: clip, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("\(clip.channelName) · \(clip.difficulty)").font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Spacing.s) {
                Button {
                    Haptics.light()
                    onPlay(clip, nil)
                } label: {
                    Label("Play clip", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.jojoOrange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button {
                    Haptics.light()
                    onPlay(clip, 0)
                } label: {
                    Label("Loop line", systemImage: "repeat")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .buttonStyle(PressableStyle())
        }
        .padding(Spacing.m)
        .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.hairlineDark, lineWidth: 1))
    }
}

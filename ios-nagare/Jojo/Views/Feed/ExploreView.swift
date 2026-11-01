import SwiftUI

/// Browsable clip library. Category lanes can lock topic or difficulty; the home grid uses the filters.
struct ExploreView: View {
    var lockedCategories: Set<ClipCategory> = []
    var lockedDifficulty: Difficulty? = nil
    var favoritesOnlyStart: Bool = false
    /// Shown first. The marketing walkthrough uses this so the two local clips are the ones on screen.
    var leadingClips: [Clip] = []
    let onPlay: (Clip, Int?, [Clip]) -> Void

    @Environment(AppModel.self) private var app
    @State private var difficulty: Difficulty?
    @State private var topic: ClipCategory?
    @State private var source: SourceType?
    @State private var favoritesOnly: Bool = false
    @State private var appeared: Bool = false

    private var filtered: [Clip] {
        let base = app.studyLibrary.filter { clip in
            let categoryOK = lockedCategories.isEmpty || lockedCategories.contains(clip.categoryKind)
            let difficultyOK = (lockedDifficulty ?? difficulty) == nil || clip.difficultyKind == (lockedDifficulty ?? difficulty)
            return categoryOK
                && difficultyOK
                && (topic == nil || clip.categoryKind == topic)
                && (source == nil || clip.categoryKind.sourceType == source)
                && (!favoritesOnly || app.isFavorite(clip.id))
        }
        guard !leadingClips.isEmpty else { return base }
        let ids = Set(leadingClips.map(\.id))
        return leadingClips + base.filter { !ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                filters
                if filtered.isEmpty {
                    VStack(spacing: Spacing.m) {
                        Image(systemName: favoritesOnly ? "bookmark" : "line.3.horizontal.decrease.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text(favoritesOnly ? "Long-press any clip or tap the bookmark to save it here." : "No clips match these filters yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Clear filters") { clearFilters() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.jojoOrange)
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVStack(spacing: Spacing.l) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, clip in
                            ExploreClipCard(clip: clip, playlist: filtered, onPlay: onPlay)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 16)
                                .animation(
                                    Motion.lineAdvance.delay(Double(min(index, 8)) * 0.045),
                                    value: appeared
                                )
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                }
            }
            .padding(.vertical, Spacing.m)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if favoritesOnlyStart { favoritesOnly = true }
            if let lockedDifficulty { difficulty = lockedDifficulty }
            withAnimation { appeared = true }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                Button {
                    Haptics.selection()
                    favoritesOnly.toggle()
                } label: {
                    FilterChip(title: "Saved", systemImage: favoritesOnly ? "bookmark.fill" : "bookmark", isSelected: favoritesOnly)
                }
                if lockedDifficulty == nil {
                    Menu {
                        Button("Any difficulty") { difficulty = nil }
                        ForEach(Difficulty.allCases) { d in
                            Button(d.rawValue) { difficulty = d }
                        }
                    } label: {
                        FilterChip(title: difficulty?.rawValue ?? "Difficulty", systemImage: "chart.bar.fill", isSelected: difficulty != nil)
                    }
                } else {
                    FilterChip(title: lockedDifficulty?.rawValue ?? "Difficulty", systemImage: "chart.bar.fill", isSelected: true)
                }
                if lockedCategories.isEmpty {
                    Menu {
                        Button("Any topic") { topic = nil }
                        ForEach(ClipCategory.allCases) { c in
                            Button { topic = c } label: { Label(c.displayName, systemImage: c.symbol) }
                        }
                    } label: {
                        FilterChip(title: topic?.displayName ?? "Topic", systemImage: "square.grid.2x2.fill", isSelected: topic != nil)
                    }
                }
                Menu {
                    Button("Any source") { source = nil }
                    ForEach(SourceType.allCases) { s in
                        Button(s.displayName) { source = s }
                    }
                } label: {
                    FilterChip(title: source?.displayName ?? "Source type", systemImage: "play.tv.fill", isSelected: source != nil)
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
    let playlist: [Clip]
    let onPlay: (Clip, Int?, [Clip]) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        Color.bgElevatedDark
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { ClipPosterView(clip: clip, showsSymbol: false).allowsHitTesting(false) }
            .overlay(alignment: .topLeading) {
                Text(clip.difficulty)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.sakuraButton, in: Capsule())
                    .padding(Spacing.s)
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
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let line = clip.lines.first {
                                Text(line.text)
                                    .font(JojoFont.jp(17, bold: true, relativeTo: .headline))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Text(clip.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            HStack(spacing: Spacing.s) {
                                Button {
                                    Haptics.light()
                                    onPlay(clip, nil, playlist)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 32)
                                        .background(Color.sakuraButton, in: Capsule())
                                }
                                Button {
                                    Haptics.light()
                                    onPlay(clip, 0, playlist)
                                } label: {
                                    Label("Loop line", systemImage: "repeat")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 32)
                                        .background(.white.opacity(0.18), in: Capsule())
                                }
                            }
                        }
                        .padding(Spacing.m)
                    }
            }
            .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.cardStroke.opacity(0.5), lineWidth: 1)
            )
            .contentShape(.rect)
            .onTapGesture {
                Haptics.light()
                onPlay(clip, nil, playlist)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(clip.title) by \(clip.channelName)")
            .accessibilityAddTraits(.isButton)
    }
}

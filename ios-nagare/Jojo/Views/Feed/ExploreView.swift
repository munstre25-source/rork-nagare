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
    @State private var filterState = ExploreFilters()
    @State private var favoritesOnly: Bool = false
    @State private var showFilters = false
    @State private var appeared: Bool = false

    private var filtered: [Clip] {
        let base = app.personalized(app.studyLibrary.filter(matchesFilters))
        let leading = leadingClips.filter(matchesFilters)
        guard !leading.isEmpty else { return base }
        var seen = Set<String>()
        return (leading + base).filter { seen.insert($0.id).inserted }
    }

    private func matchesFilters(_ clip: Clip) -> Bool {
        matches(clip, filterState)
    }

    private func matches(_ clip: Clip, _ f: ExploreFilters) -> Bool {
        let selectedDifficulty = lockedDifficulty ?? f.difficulty
        guard (lockedCategories.isEmpty || lockedCategories.contains(clip.categoryKind)),
              selectedDifficulty == nil || clip.difficultyKind == selectedDifficulty,
              f.topic == nil || clip.categoryKind == f.topic,
              f.source == nil || clip.categoryKind.sourceType == f.source,
              !favoritesOnly || app.isFavorite(clip.id) else { return false }
        switch f.watched {
        case .any: break
        case .watched: guard app.profile.finishedClipIds.contains(clip.id) else { return false }
        case .unwatched: guard !app.profile.finishedClipIds.contains(clip.id) else { return false }
        }
        if let grammar = f.grammar, !grammar.matches(clip) { return false }
        return true
    }

    private var hasActiveFilters: Bool {
        filterState.activeCount > (lockedDifficulty == nil ? 0 : 1) || favoritesOnly
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
            if let lockedDifficulty { filterState.difficulty = lockedDifficulty }
            withAnimation { appeared = true }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                Button {
                    Haptics.selection()
                    showFilters = true
                } label: {
                    let extra = filterState.activeCount - (lockedDifficulty == nil ? 0 : 1)
                    FilterChip(title: extra > 0 ? "Filters · \(extra)" : "Filters",
                               systemImage: "line.3.horizontal.decrease", isSelected: extra > 0)
                }
                .accessibilityHint("Difficulty, grammar, topic, source and watched")
                Button {
                    Haptics.selection()
                    favoritesOnly.toggle()
                } label: {
                    FilterChip(title: "Saved", systemImage: favoritesOnly ? "bookmark.fill" : "bookmark", isSelected: favoritesOnly)
                }
                if let lockedDifficulty {
                    FilterChip(title: lockedDifficulty.rawValue, systemImage: "chart.bar.fill", isSelected: true)
                } else if let d = filterState.difficulty {
                    activeChip(d.rawValue, symbol: "chart.bar.fill") { filterState.difficulty = nil }
                }
                if let g = filterState.grammar {
                    activeChip(g.title, symbol: "text.book.closed.fill") { filterState.grammar = nil }
                }
                if let t = filterState.topic {
                    activeChip(t.displayName, symbol: t.symbol) { filterState.topic = nil }
                }
                if let s = filterState.source {
                    activeChip(s.displayName, symbol: "play.tv.fill") { filterState.source = nil }
                }
                if filterState.watched != .any {
                    activeChip(filterState.watched.title, symbol: "eye.fill") { filterState.watched = .any }
                }
                if hasActiveFilters {
                    Button("Clear") { clearFilters() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.jojoOrange)
                        .frame(minHeight: 44)
                }
            }
        }
        .contentMargins(.horizontal, Spacing.l, for: .scrollContent)
        .sheet(isPresented: $showFilters) {
            ExploreFiltersSheet(
                filters: $filterState,
                lockedDifficulty: lockedDifficulty,
                lockTopic: !lockedCategories.isEmpty,
                count: { draft in app.studyLibrary.filter { matches($0, draft) }.count }
            )
        }
    }

    private func activeChip(_ title: String, symbol: String, remove: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { remove() }
        } label: {
            FilterChip(title: "\(title)  ✕", systemImage: symbol, isSelected: true)
        }
        .accessibilityLabel("Remove \(title) filter")
    }

    private func clearFilters() {
        withAnimation(.snappy) {
            filterState = ExploreFilters(difficulty: lockedDifficulty)
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

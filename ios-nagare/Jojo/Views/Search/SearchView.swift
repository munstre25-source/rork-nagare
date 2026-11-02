import SwiftUI

nonisolated enum SearchScope: String, CaseIterable, Hashable, Sendable {
    case all = "All"
    case words = "Words"
    case sentences = "Clips"
    case grammar = "Grammar"

    func hasLocalResults(wordCount: Int, clipCount: Int, grammarCount: Int) -> Bool {
        switch self {
        case .all: wordCount + clipCount + grammarCount > 0
        case .words: wordCount > 0
        case .sentences: clipCount > 0
        case .grammar: grammarCount > 0
        }
    }
}

/// State of the whole-catalog (server) search under the local results.
nonisolated enum RemoteSearchState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

struct WordSearchHit: Identifiable, Hashable, Sendable {
    var surface: String
    var reading: String
    var romaji: String
    var gloss: String
    var jlpt: String?
    var pos: String
    var id: String { "\(surface)|\(reading)|\(pos)" }
}

/// Search words, sentences, and grammar. Opened from Explore, and as a sheet from the feed.
struct SearchView: View {
    var initialQuery: String = ""
    var initialScope: SearchScope = .all
    var embedded: Bool = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var didInitialize = false
    @State private var scope: SearchScope = .all
    @State private var showAllWords = false
    @State private var showAllSentences = false
    @State private var playing: SearchHit?
    // Kiku's signature: search the whole catalog on the server, then open the clip at the line.
    @State private var remoteHits: [SearchHit]? = nil
    @State private var remoteState: RemoteSearchState = .idle
    @State private var pattern: GrammarPattern? = nil
    @State private var patternHits: [SearchHit]? = nil
    @State private var patternState: RemoteSearchState = .idle
    @FocusState private var isFocused: Bool

    private let suggestions = ["好き", "天気", "たべる", "大丈夫", "ことば", "猫"]
    private let grammarPOS: Set<String> = ["particle", "auxiliary", "copula", "conjunction", "expression", "grammar", "suffix", "prefix"]

    var body: some View {
        Group {
            if embedded {
                page.navigationBarTitleDisplayMode(.inline)
            } else {
                NavigationStack {
                    page
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            if query.isEmpty { query = initialQuery }
            if scope == .all { scope = initialScope }
            isFocused = initialQuery.isEmpty && !embedded
        }
        .onChange(of: query) { _, _ in
            showAllWords = false
            showAllSentences = false
            remoteHits = nil
            remoteState = .idle
            pattern = nil
            patternHits = nil
            patternState = .idle
        }
        .task(id: "\(query)|\(scope)") {
            await runRemoteSearch()
        }
        .task(id: "\(scope)|\(pattern?.id ?? "")") {
            guard scope == .grammar, let pattern else { return }
            await loadPatternHits(pattern)
        }
        .fullScreenCover(item: $playing) { hit in
            ClipPlayerScreen(clip: hit.clip, startLine: hit.lineIndex, loopLine: true)
                .environment(app)
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Search.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LearningInk.japanese)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textGlow(LearningInk.glow, level: app.profile.glow)
                Text("Search a word, then hear it in a real clip.")
                    .font(.subheadline)
                    .foregroundStyle(Color.studyMuted)
                    .lineLimit(2)
                DesignSearchField(text: $query, placeholder: "Search kanji, kana or romaji", focused: $isFocused)
                if isFocused {
                    Text("Japanese works here. Switch keyboards with the globe key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OrangePillBar(items: SearchScope.allCases, selection: $scope, title: \.rawValue)
                results
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(Color.studyPage.ignoresSafeArea())
    }

    @ViewBuilder
    private var results: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if scope == .grammar {
                grammarBrowse
            } else {
                suggestionsView
            }
        } else {
            if !scope.hasLocalResults(wordCount: wordHits.count, clipCount: sentenceHits.count,
                                      grammarCount: grammarHits.count) && showsNoRemoteResults {
                Text("No matches for \u{201C}\(trimmed)\u{201D} in this search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            resultSummary
            if scope == .all || scope == .words, !wordHits.isEmpty {
                resultSection(
                    title: "Words (\(wordHits.count))",
                    expanded: showAllWords,
                    canExpand: wordHits.count > 4,
                    expandTitle: "See all words"
                ) {
                    showAllWords.toggle()
                } content: {
                    ForEach(visibleWords) { hit in
                        DictionaryResultRow(hit: hit) { findClips(for: hit.surface) }
                    }
                }
            }
            if scope == .all || scope == .sentences, !sentenceHits.isEmpty {
                resultSection(
                    title: "Available clips (\(sentenceHits.count))",
                    expanded: showAllSentences,
                    canExpand: sentenceHits.count > 8,
                    expandTitle: "See all clips"
                ) {
                    showAllSentences.toggle()
                } content: {
                    ForEach(visibleSentences) { hit in
                        Button {
                            Haptics.light()
                            playing = hit
                        } label: {
                            SentenceResultRow(hit: hit, query: trimmed)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if scope == .all || scope == .sentences {
                remoteSection(trimmed: trimmed)
            }
            if scope == .all || scope == .grammar, !grammarHits.isEmpty {
                resultSection(
                    title: "Grammar (\(grammarHits.count))",
                    expanded: true,
                    canExpand: false,
                    expandTitle: ""
                ) {} content: {
                    ForEach(grammarHits.prefix(scope == .grammar ? 40 : 6)) { hit in
                        DictionaryResultRow(hit: hit) { findClips(for: hit.surface) }
                    }
                }
            }
            if scope == .grammar, let pattern {
                patternResults(pattern: pattern)
            }
        }
    }

    // MARK: Kiku search: the whole catalog, on the server

    private var showsNoRemoteResults: Bool {
        guard scope == .all || scope == .sentences else { return true }
        switch remoteState {
        case .loaded: return (remoteHits ?? []).isEmpty
        case .loading: return false
        case .failed: return false
        case .idle: return true
        }
    }

    /// Server results under the local ones; hits already shown locally are not repeated.
    @ViewBuilder
    private func remoteSection(trimmed: String) -> some View {
        let localIds = Set(sentenceHits.map(\.id))
        let hits = (remoteHits ?? []).filter { !localIds.contains($0.id) }
        switch remoteState {
        case .loading:
            resultSection(title: "All clips", expanded: true, canExpand: false, expandTitle: "") {} content: {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching the whole library\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
            }
        case .loaded:
            if !hits.isEmpty {
                resultSection(
                    title: "More clips (\(hits.count))",
                    expanded: true,
                    canExpand: false,
                    expandTitle: ""
                ) {} content: {
                    ForEach(hits) { hit in
                        Button {
                            Haptics.light()
                            playing = hit
                        } label: {
                            SentenceResultRow(hit: hit, query: trimmed)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .failed:
            Text("Couldn't reach the library. Local results are shown.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        case .idle:
            EmptyView()
        }
    }

    /// Grammar scope with an empty field: browse points, then see every line in the
    /// library that uses one.
    private var grammarBrowse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Grammar points")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(GrammarPattern.all) { item in
                    Button {
                        Haptics.selection()
                        pattern = item
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(JojoFont.jp(16, relativeTo: .body))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if let jlpt = item.jlpt {
                                    Text(jlpt)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color.studyAccent)
                                }
                            }
                            Text(item.meaning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(pattern == item ? Color.studyAccent : Color.cardStroke, lineWidth: pattern == item ? 1.6 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            if let pattern {
                patternResults(pattern: pattern)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func patternResults(pattern: GrammarPattern) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(pattern.title) \u{2014} \(pattern.meaning)")
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            switch patternState {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding every line that uses it\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
            case .loaded:
                let hits = patternHits ?? []
                if hits.isEmpty {
                    Text("No lines use this yet. New clips are added every day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(hits) { hit in
                        Button {
                            Haptics.light()
                            playing = hit
                        } label: {
                            SentenceResultRow(hit: hit, query: pattern.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .failed, .idle:
                Text("Couldn't reach the library. Try again in a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
    }

    private func runRemoteSearch() async {
        // The Grammar scope searches by pattern chips, not by word.
        guard scope == .all || scope == .sentences else {
            remoteHits = nil
            remoteState = .idle
            return
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, SupabaseAPI.shared.isConfigured else {
            remoteHits = nil
            remoteState = .idle
            return
        }
        remoteHits = nil
        remoteState = .loading
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        do {
            let hits = try await SupabaseAPI.shared.searchLines(query: q)
            guard !Task.isCancelled else { return }
            remoteHits = hits
            remoteState = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            remoteHits = nil
            remoteState = .failed
        }
    }

    private func loadPatternHits(_ pattern: GrammarPattern) async {
        patternHits = nil
        guard SupabaseAPI.shared.isConfigured else {
            patternState = .failed
            return
        }
        patternState = .loading
        patternHits = nil
        do {
            let hits = try await SupabaseAPI.shared.searchGrammar(patternId: pattern.id)
            guard !Task.isCancelled, self.pattern?.id == pattern.id, scope == .grammar else { return }
            patternHits = hits
            patternState = .loaded
        } catch {
            guard !Task.isCancelled, self.pattern?.id == pattern.id, scope == .grammar else { return }
            patternState = .failed
        }
    }

    private func findClips(for surface: String) {
        Haptics.selection()
        query = surface
        scope = .sentences
        isFocused = false
    }

    private var resultSummary: some View {
        var parts: [String] = []
        if scope == .all || scope == .words, !wordHits.isEmpty {
            parts.append(wordHits.count == 1 ? "1 word" : "\(wordHits.count) words")
        }
        if scope == .all || scope == .sentences {
            let count = Set((sentenceHits + (remoteHits ?? [])).map(\.id)).count
            if count > 0 { parts.append(count == 1 ? "1 clip" : "\(count) clips") }
        }
        if scope == .all || scope == .grammar, !grammarHits.isEmpty {
            parts.append(grammarHits.count == 1 ? "1 grammar point" : "\(grammarHits.count) grammar")
        }
        return Text(parts.joined(separator: " · "))
            .font(.title3.weight(.bold))
            .foregroundStyle(LearningInk.japanese)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var visibleWords: [WordSearchHit] {
        showAllWords || scope == .words ? wordHits : Array(wordHits.prefix(4))
    }

    private var visibleSentences: [SearchHit] {
        showAllSentences || scope == .sentences ? sentenceHits : Array(sentenceHits.prefix(8))
    }

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try searching")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.selection()
                        query = suggestion
                    } label: {
                        Text(suggestion)
                            .font(JojoFont.jp(16, relativeTo: .body))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.cardStroke))
                    }
                }
            }
        }
    }

    private func resultSection<Content: View>(
        title: String,
        expanded: Bool,
        canExpand: Bool,
        expandTitle: String,
        toggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            VStack(spacing: 0) {
                content()
            }
            if canExpand && !expanded {
                Button(action: toggle) {
                    HStack(spacing: 4) {
                        Text(expandTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.studyAccent)
                    .frame(minHeight: 36)
                }
            }
        }
        .padding(.top, 6)
    }

    private var wordHits: [WordSearchHit] {
        collectedWords.filter { !grammarPOS.contains($0.pos) }
    }

    private var grammarHits: [WordSearchHit] {
        collectedWords.filter { grammarPOS.contains($0.pos) }
    }

    private var sentenceHits: [SearchHit] {
        SearchMatcher.search(query, in: app.studyLibrary)
    }

    private var collectedWords: [WordSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var hits: [WordSearchHit] = []

        func add(_ hit: WordSearchHit) {
            guard seen.insert(hit.id).inserted else { return }
            hits.append(hit)
        }

        for entry in app.lexicon.entries.values where matches(surface: entry.surface, reading: entry.readings.first ?? "", romaji: entry.romaji, gloss: entry.definitions.first ?? "") {
            add(WordSearchHit(
                surface: entry.surface,
                reading: entry.readings.first ?? "",
                romaji: entry.romaji,
                gloss: entry.definitions.prefix(2).joined(separator: "; "),
                jlpt: entry.jlpt,
                pos: entry.pos
            ))
        }

        for clip in app.studyLibrary {
            for line in clip.lines {
                for token in line.tokens where token.tappable && SearchMatcher.tokenMatches(token, query: q) {
                    add(WordSearchHit(
                        surface: token.surface,
                        reading: token.reading ?? token.baseReading ?? "",
                        romaji: token.romaji,
                        gloss: token.definitions.first ?? "",
                        jlpt: token.jlpt,
                        pos: token.pos
                    ))
                }
            }
        }

        return hits.sorted { lhs, rhs in
            if lhs.surface.count != rhs.surface.count { return lhs.surface.count < rhs.surface.count }
            return lhs.surface < rhs.surface
        }
    }

    private func matches(surface: String, reading: String, romaji: String, gloss: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        if surface.contains(q) || gloss.localizedStandardContains(q) { return true }
        let hq = JapaneseText.hiragana(q)
        if JapaneseText.hiragana(surface).contains(hq) || JapaneseText.hiragana(reading).contains(hq) { return true }
        let nq = JapaneseText.normalizedRomaji(q)
        if nq.count >= 2, JapaneseText.normalizedRomaji(romaji).contains(nq) { return true }
        return false
    }
}

private struct DictionaryResultRow: View {
    let hit: WordSearchHit
    let onFindClips: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onFindClips) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        if app.profile.showFurigana, !hit.reading.isEmpty, hit.reading != hit.surface {
                            Text(hit.reading).font(JojoFont.jp(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                        Text(hit.surface).font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                            .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                        if app.profile.showRomaji, !hit.romaji.isEmpty {
                            Text(hit.romaji).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !hit.gloss.isEmpty {
                            Text(hit.gloss).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    if let jlpt = hit.jlpt { JLPTBadge(level: jlpt) }
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Find clips using \(hit.surface)")
            Button {
                SpeechService.shared.speak(hit.surface)
            } label: {
                Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Hear \(hit.surface)")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 8)
    }
}

private struct SentenceResultRow: View {
    @Environment(AppModel.self) private var app
    let hit: SearchHit
    var query: String = ""

    private var line: Line? { hit.clip.lines[safe: hit.lineIndex] }

    private var matchedSurface: String {
        guard let line else { return query }
        if let token = line.tokens.first(where: { SearchMatcher.tokenMatches($0, query: query) }) {
            return token.surface
        }
        return query
    }

    private var level: String? {
        line?.tokens.first(where: { SearchMatcher.tokenMatches($0, query: query) })?.jlpt
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ClipPosterView(clip: hit.clip, showsSymbol: false)
                .frame(width: 84, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HighlightedSentence(
                    sentence: line?.text ?? hit.clip.title,
                    target: matchedSurface,
                    size: 16,
                    baseColor: .primary,
                    lineLimit: 2
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(hit.clip.channelName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.studyMuted)
                    .lineLimit(1)
                if app.profile.subtitleDisplay.english == .shown, let translation = line?.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let level {
                JLPTBadge(level: level)
            } else {
                Text(hit.clip.difficulty).font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.studyMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
    }
}

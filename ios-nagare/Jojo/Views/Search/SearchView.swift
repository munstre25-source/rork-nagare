import SwiftUI

nonisolated enum SearchScope: String, CaseIterable, Hashable, Sendable {
    case all = "All"
    case words = "Words"
    case sentences = "Clips"
    case grammar = "Grammar"
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
    @State private var scope: SearchScope = .all
    @State private var showAllWords = false
    @State private var showAllSentences = false
    @State private var playing: SearchHit?
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
            if query.isEmpty { query = initialQuery }
            if scope == .all { scope = initialScope }
            isFocused = initialQuery.isEmpty && !embedded
        }
        .onChange(of: query) { _, _ in
            showAllWords = false
            showAllSentences = false
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("See a word, a grammar point, or a phrase used in real clips.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var results: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestionsView
        } else if visibleWords.isEmpty && visibleSentences.isEmpty && grammarHits.isEmpty {
            Text("No matches for “\(trimmed)” yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        } else {
            resultSummary
            if scope == .all || scope == .sentences, !sentenceHits.isEmpty {
                resultSection(
                    title: "Clips (\(sentenceHits.count))",
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
                        DictionaryResultRow(hit: hit)
                    }
                }
            }
            if scope == .all || scope == .grammar, !grammarHits.isEmpty {
                resultSection(
                    title: "Grammar (\(grammarHits.count))",
                    expanded: true,
                    canExpand: false,
                    expandTitle: ""
                ) {} content: {
                    ForEach(grammarHits.prefix(scope == .grammar ? 40 : 6)) { hit in
                        DictionaryResultRow(hit: hit)
                    }
                }
            }
        }
    }

    private var resultSummary: some View {
        var parts: [String] = []
        if scope == .all || scope == .sentences, !sentenceHits.isEmpty {
            parts.append(sentenceHits.count == 1 ? "1 clip" : "\(sentenceHits.count) clips")
        }
        if scope == .all || scope == .words, !wordHits.isEmpty {
            parts.append(wordHits.count == 1 ? "1 word" : "\(wordHits.count) words")
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

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.surface)
                    .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !hit.romaji.isEmpty {
                    Text(hit.romaji)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !hit.gloss.isEmpty {
                    Text(hit.gloss)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                SpeechService.shared.speak(hit.surface)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(hit.surface)")
            if let jlpt = hit.jlpt {
                JLPTBadge(level: jlpt)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
    }
}

private struct SentenceResultRow: View {
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
        if let tokenLevel = line?.tokens.compactMap(\.jlpt).first { return tokenLevel }
        switch hit.clip.difficultyKind {
        case .beginner: return "N5"
        case .intermediate: return "N4"
        case .advanced: return "N3"
        }
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
                if let translation = line?.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let level {
                JLPTBadge(level: level)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
    }
}

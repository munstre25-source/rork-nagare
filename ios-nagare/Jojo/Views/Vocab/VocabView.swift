import SwiftUI
import SwiftData

nonisolated enum VocabSection: String, CaseIterable, Sendable {
    case review = "Review"
    case all = "All Words"
}

nonisolated enum VocabSort: String, CaseIterable, Sendable {
    case recent = "Recently added"
    case frequent = "Most seen"
}

/// Vocab tab: Review | All Words. Follows system light/dark.
struct VocabView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \SavedWord.addedAt, order: .reverse) private var words: [SavedWord]
    @Query(sort: \CustomDeck.createdAt) private var decks: [CustomDeck]
    @State private var section: VocabSection = .all
    @State private var query: String = ""
    @State private var sort: VocabSort = .recent
    @State private var jlpt: String?
    @State private var posFilter: StudyPosFilter = .all
    @State private var sourceChannel: String?
    @State private var reviewSession: ReviewSessionConfig?
    @State private var showDeckBuilder: Bool = false
    @State private var showSearch: Bool = false

    private var filtered: [SavedWord] {
        var result = words
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let hq = JapaneseText.hiragana(q)
            let nq = JapaneseText.normalizedRomaji(q)
            result = result.filter { word in
                word.surface.contains(q)
                    || word.readings.contains { JapaneseText.hiragana($0).contains(hq) }
                    || JapaneseText.normalizedRomaji(word.romaji).contains(nq)
                    || word.definitions.contains { $0.localizedStandardContains(q) }
                    || word.jaDefinitions.contains { $0.localizedStandardContains(q) }
            }
        }
        if let jlpt { result = result.filter { $0.jlpt == jlpt } }
        if posFilter != .all { result = result.filter { posFilter.matches($0.pos) } }
        if let sourceChannel {
            result = result.filter { app.clip(id: $0.contextClipId)?.channelName == sourceChannel }
        }
        if sort == .frequent { result.sort { $0.occurrenceCount > $1.occurrenceCount } }
        return result
    }

    private var dueWords: [SavedWord] {
        words.filter { $0.dueAt <= Date() }.sorted { $0.dueAt < $1.dueAt }
    }

    private var channels: [String] {
        Array(Set(words.compactMap { app.clip(id: $0.contextClipId)?.channelName })).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Picker("Section", selection: $section) {
                        ForEach(VocabSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Spacing.l)

                    switch section {
                    case .all: allWords
                    case .review: reviewHub
                    }
                }
                .padding(.vertical, Spacing.s)
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Vocab")
            .navigationDestination(for: String.self) { key in
                if let word = words.first(where: { $0.key == key }) {
                    WordDetailView(word: word)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "text.magnifyingglass")
                    }
                    .tint(.jojoOrange)
                    .accessibilityLabel("Search & Listen in clips")
                }
            }
        }
        .fullScreenCover(item: $reviewSession) { config in
            ReviewSessionView(config: config)
        }
        .sheet(isPresented: $showDeckBuilder) {
            CustomDeckBuilder()
        }
        .sheet(isPresented: $showSearch) {
            SearchView(initialQuery: query)
        }
        .onAppear { openPendingReviewIfNeeded() }
        .onChange(of: app.pendingDeepLink) { _, _ in openPendingReviewIfNeeded() }
    }

    private func openPendingReviewIfNeeded() {
        guard app.pendingDeepLink == .review else { return }
        app.clearDeepLink()
        section = .review
        let pool = dueWords.isEmpty ? words : dueWords
        startReview(Array(pool), title: "Review")
    }

    // MARK: All Words

    private var allWords: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search kanji, kana or romaji", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, Spacing.m)
            .frame(minHeight: 48)
            .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, Spacing.l)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    Menu {
                        ForEach(VocabSort.allCases, id: \.self) { s in
                            Button(s.rawValue) { sort = s }
                        }
                    } label: {
                        FilterChip(title: sort.rawValue, isSelected: true)
                    }
                    Menu {
                        Button("Any level") { jlpt = nil }
                        ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { level in
                            Button(level) { jlpt = level }
                        }
                    } label: {
                        FilterChip(title: jlpt ?? "JLPT", isSelected: jlpt != nil)
                    }
                    Menu {
                        ForEach(StudyPosFilter.allCases) { filter in
                            Button(filter.title) { posFilter = filter }
                        }
                    } label: {
                        FilterChip(title: posFilter == .all ? "Word type" : posFilter.title, isSelected: posFilter != .all)
                    }
                    Menu {
                        Button("Any source") { sourceChannel = nil }
                        ForEach(channels, id: \.self) { channel in
                            Button(channel) { sourceChannel = channel }
                        }
                    } label: {
                        FilterChip(title: sourceChannel ?? "Source", isSelected: sourceChannel != nil)
                    }
                    Button {
                        showDeckBuilder = true
                    } label: {
                        FilterChip(title: "Custom deck", systemImage: "plus")
                    }
                }
            }
            .contentMargins(.horizontal, Spacing.l, for: .scrollContent)

            Button {
                let dueFiltered = dueWords.filter { word in
                    (jlpt == nil || word.jlpt == jlpt) && posFilter.matches(word.pos)
                }
                let pool = dueFiltered.isEmpty ? filtered : dueFiltered
                startReview(Array(pool), title: "Review")
            } label: {
                let dueFilteredCount = dueWords.filter { (jlpt == nil || $0.jlpt == jlpt) && posFilter.matches($0.pos) }.count
                let count = min(10, dueFilteredCount == 0 ? filtered.count : dueFilteredCount)
                Label("Review \(count) cards", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(words.isEmpty)
            .padding(.horizontal, Spacing.l)

            if filtered.isEmpty {
                VStack(spacing: Spacing.s) {
                    Image(systemName: "character.book.closed.ja").font(.largeTitle).foregroundStyle(.secondary)
                    Text(words.isEmpty ? "Tap any word in the Feed and it lands here." : "No words match.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { word in
                        NavigationLink(value: word.key) {
                            VocabRow(word: word)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 70)
                    }
                }
            }
        }
    }

    // MARK: Review hub

    private var reviewHub: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("\(dueWords.count)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(dueWords.isEmpty ? "All caught up. New taps show up here in 10 minutes." : "cards due now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    startReview(dueWords.isEmpty ? Array(words.shuffled()) : dueWords, title: "Review")
                } label: {
                    Label(dueWords.isEmpty ? "Practice 10 cards anyway" : "Review \(min(10, dueWords.count)) cards", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(words.isEmpty)
                .padding(.top, Spacing.s)
            }
            .padding(Spacing.l)
            .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.cardStroke))
            .padding(.horizontal, Spacing.l)

            HStack {
                Text("Custom decks").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    showDeckBuilder = true
                } label: {
                    Label("New", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .tint(.jojoOrange)
            }
            .padding(.horizontal, Spacing.l)

            VStack(spacing: Spacing.s) {
                ForEach(decks) { deck in
                    let matching = deckWords(deck)
                    Button {
                        startReview(matching, title: deck.name)
                    } label: {
                        DeckRow(title: deck.name, subtitle: "\(matching.count) words · \(deck.filterKind == "channel" ? "Show" : "Topic")", symbol: deck.filterKind == "channel" ? "person.crop.square" : "square.grid.2x2")
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(matching.isEmpty)
                    .contextMenu {
                        Button(role: .destructive) {
                            app.context.delete(deck)
                            app.save()
                        } label: { Label("Delete deck", systemImage: "trash") }
                    }
                }
                ForEach(["N5", "N4", "N3"], id: \.self) { level in
                    let levelWords = words.filter { $0.jlpt == level }
                    if !levelWords.isEmpty {
                        Button {
                            startReview(levelWords, title: "JLPT \(level)")
                        } label: {
                            DeckRow(title: "JLPT \(level)", subtitle: "\(levelWords.count) words", symbol: "graduationcap")
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, Spacing.l)
        }
    }

    private func deckWords(_ deck: CustomDeck) -> [SavedWord] {
        words.filter { word in
            guard let clip = app.clip(id: word.contextClipId) else { return false }
            return deck.filterKind == "channel" ? clip.channelName == deck.filterValue : clip.category == deck.filterValue
        }
    }

    private func startReview(_ source: [SavedWord], title: String) {
        let keys = Array(source.prefix(10).map(\.key))
        guard !keys.isEmpty else { return }
        Haptics.medium()
        reviewSession = ReviewSessionConfig(title: title, keys: keys)
    }
}

struct VocabRow: View {
    let word: SavedWord
    @Environment(AppModel.self) private var app

    private var gloss: String {
        word.displayDefinitions(mode: app.profile.dictionary).first ?? word.gloss
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            OccurrenceBadge(count: word.occurrenceCount, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                if app.profile.showFurigana, !word.primaryReading.isEmpty {
                    Text(word.primaryReading)
                        .font(JojoFont.jp(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                Text(word.surface)
                    .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                    .foregroundStyle(.primary)
                Text(gloss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                SpeechService.shared.speak(word.surface)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Play \(word.surface)")
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.surface), \(word.primaryReading), \(gloss), seen \(word.occurrenceCount) times")
    }
}

private struct DeckRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.jojoOrange)
                .frame(width: 44, height: 44)
                .background(Color.jojoOrangeSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Color.jojoOrange)
        }
        .padding(Spacing.m)
        .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardStroke))
    }
}

/// Create a deck filtered by show/channel or topic.
struct CustomDeckBuilder: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var channels: [String] { Array(Set(app.clips.map(\.channelName))).sorted() }

    var body: some View {
        NavigationStack {
            List {
                Section("By show / channel") {
                    ForEach(channels, id: \.self) { channel in
                        Button {
                            create(name: channel, kind: "channel", value: channel)
                        } label: {
                            Label(channel, systemImage: "person.crop.square")
                        }
                    }
                }
                Section("By topic") {
                    ForEach(ClipCategory.allCases) { category in
                        Button {
                            create(name: category.displayName, kind: "topic", value: category.rawValue)
                        } label: {
                            Label(category.displayName, systemImage: category.symbol)
                        }
                    }
                }
            }
            .tint(.primary)
            .navigationTitle("New custom deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func create(name: String, kind: String, value: String) {
        app.context.insert(CustomDeck(name: name, filterKind: kind, filterValue: value))
        app.save()
        Haptics.success()
        dismiss()
    }
}

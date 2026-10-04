import SwiftUI
import SwiftData

nonisolated enum VocabSection: String, CaseIterable, Sendable, Hashable {
    case learn = "Learn"
    case mine = "My Words"
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
    @State private var section: VocabSection = .learn
    @State private var query: String = ""
    @State private var sort: VocabSort = .recent
    @State private var jlpt: String?
    @State private var posFilter: StudyPosFilter = .all
    @State private var sourceChannel: String?
    @State private var reviewSession: ReviewSessionConfig?
    @State private var showDeckBuilder: Bool = false
    @State private var showFilters: Bool = false
    var tabBarHidden: Binding<Bool> = .constant(false)

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

    private var reviewedToday: Int {
        words.filter { word in
            guard let date = word.lastReviewedAt else { return false }
            return Calendar.current.isDateInToday(date)
        }.count
    }

    private var focusWord: SavedWord? { dueWords.first ?? words.first }

    private var mostTapped: [SavedWord] {
        Array(words.sorted { $0.occurrenceCount > $1.occurrenceCount }.prefix(8).filter { $0.occurrenceCount > 1 })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vocab")
                            .font(.system(size: 34, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Grow your vocabulary, one word at a time.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        DesignSearchField(text: $query, placeholder: "Search words...")
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 48, height: 48)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
                        }
                        .accessibilityLabel("Filter words")
                    }

                    OrangePillBar(items: VocabSection.allCases, selection: $section, title: \.rawValue)

                    switch section {
                    case .learn: learnSection
                    case .mine: myWordsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .tabBarAutoHide(tabBarHidden)
            .background(Color.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { key in
                if let word = words.first(where: { $0.key == key }) {
                    WordDetailView(word: word)
                }
            }
        }
        .fullScreenCover(item: $reviewSession) { config in
            ReviewSessionView(config: config)
        }
        .sheet(isPresented: $showDeckBuilder) {
            CustomDeckBuilder()
        }
        .sheet(isPresented: $showFilters) {
            VocabFilterSheet(
                sort: $sort,
                jlpt: $jlpt,
                posFilter: $posFilter,
                sourceChannel: $sourceChannel,
                channels: channels,
                onNewDeck: { showDeckBuilder = true }
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear { openPendingReviewIfNeeded() }
        .onChange(of: app.pendingDeepLink) { _, _ in openPendingReviewIfNeeded() }
    }

    private var learnSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let focusWord {
                todaysFocus(focusWord)
            } else {
                emptyVocab
            }
            if !mostTapped.isEmpty {
                Text("Words you keep meeting")
                    .font(.title3.weight(.bold))
                VStack(spacing: 10) {
                    ForEach(mostTapped) { word in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.surface)
                                    .font(JojoFont.jp(20, bold: true, relativeTo: .title3))
                                    .lineLimit(1)
                                Text("\(word.occurrenceCount) taps · \(word.state.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Button("Known") { app.paint(word, mark: .known) }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(word.state == .known ? .white : Color.designOrange)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 32)
                                .background(word.state == .known ? Color.designOrange : Color.designOrange.opacity(0.12), in: Capsule())
                        }
                        .padding(12)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            if !filtered.isEmpty {
                Text("All Vocabulary")
                    .font(.title3.weight(.bold))
                VStack(spacing: 10) {
                    ForEach(Array(filtered.enumerated()), id: \.element.key) { index, word in
                        NavigationLink(value: word.key) {
                            NumberedVocabRow(index: index + 1, word: word)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func todaysFocus(_ word: SavedWord) -> some View {
        let gloss = word.displayDefinitions(mode: app.profile.dictionary).first ?? word.gloss
        let done = min(reviewedToday, 10)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Today’s focus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.designOrange)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(word.surface)
                            .font(JojoFont.jp(32, bold: true, relativeTo: .largeTitle))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Button {
                            SpeechService.shared.speak(word.surface)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.designOrange)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Play \(word.surface)")
                    }
                    if !word.primaryReading.isEmpty {
                        Text(word.primaryReading)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(gloss)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("\(done)/10")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: 10)
                .tint(Color.designOrange)
            Button {
                let pool = dueWords.isEmpty ? Array(words) : dueWords
                startReview(pool, title: "Today’s focus")
            } label: {
                Text(dueWords.isEmpty ? "Practice 10 cards" : "Review \(min(10, dueWords.count)) cards")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(Color.sakuraFill, in: Capsule())
            }
            .disabled(words.isEmpty)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.designOrange.opacity(0.16), Color.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.designOrange.opacity(0.18)))
    }

    private var myWordsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if filtered.isEmpty {
                emptyVocab
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(filtered.enumerated()), id: \.element.key) { index, word in
                        NavigationLink(value: word.key) {
                            NumberedVocabRow(index: index + 1, word: word)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            decksSection
        }
    }

    private var emptyVocab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No words yet")
                .font(.headline)
            Text("Tap a word in the feed and it lands here, ready to review.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
    }

    private var decksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Decks")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    showDeckBuilder = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .tint(Color.designOrange)
            }
            VStack(spacing: 10) {
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
        }
    }
    private func openPendingReviewIfNeeded() {
        guard app.pendingDeepLink == .review else { return }
        app.clearDeepLink()
        section = .learn
        let pool = dueWords.isEmpty ? words : dueWords
        startReview(Array(pool), title: "Review")
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
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

struct NumberedVocabRow: View {
    let index: Int
    let word: SavedWord
    @Environment(AppModel.self) private var app

    private var gloss: String {
        word.displayDefinitions(mode: app.profile.dictionary).first ?? word.gloss
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.sakuraFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(word.surface)
                    .font(JojoFont.jp(20, bold: true, relativeTo: .title3))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    if !word.primaryReading.isEmpty {
                        Text(word.primaryReading)
                            .lineLimit(1)
                    }
                    Text(gloss)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                SpeechService.shared.speak(word.surface)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(word.surface)")
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
    }
}

private struct VocabFilterSheet: View {
    @Binding var sort: VocabSort
    @Binding var jlpt: String?
    @Binding var posFilter: StudyPosFilter
    @Binding var sourceChannel: String?
    let channels: [String]
    let onNewDeck: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sort") {
                    ForEach(VocabSort.allCases, id: \.self) { option in
                        Button(option.rawValue) { sort = option }
                    }
                }
                Section("JLPT") {
                    Button("Any level") { jlpt = nil }
                    ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { level in
                        Button(level) { jlpt = level }
                    }
                }
                Section("Word type") {
                    ForEach(StudyPosFilter.allCases) { filter in
                        Button(filter.title) { posFilter = filter }
                    }
                }
                Section("Source") {
                    Button("Any source") { sourceChannel = nil }
                    ForEach(channels, id: \.self) { channel in
                        Button(channel) { sourceChannel = channel }
                    }
                }
                Section {
                    Button("New custom deck") {
                        dismiss()
                        onNewDeck()
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

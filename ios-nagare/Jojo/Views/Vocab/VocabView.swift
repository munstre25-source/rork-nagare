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
    @State private var buildDeckAfterFilters = false
    @State private var showClipSearch = false
    var tabBarHidden: Binding<Bool> = .constant(false)

    private var filtered: [SavedWord] {
        var result = words
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let hq = JapaneseText.hiragana(q)
            let nq = JapaneseText.normalizedRomaji(q)
            result = result.filter { word in
                JapaneseText.hiragana(word.surface).contains(hq)
                    || word.readings.contains { JapaneseText.hiragana($0).contains(hq) }
                    || (!nq.isEmpty && JapaneseText.normalizedRomaji(word.romaji).contains(nq))
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
        _ = app.reviewAvailabilityRevision
        return ReviewQueue.due(in: words)
    }

    private var hasFilters: Bool { jlpt != nil || posFilter != .all || sourceChannel != nil }

    private var channels: [String] {
        Array(Set(words.compactMap { app.clip(id: $0.contextClipId)?.channelName })).sorted()
    }


    private var reviewPool: [SavedWord] {
        _ = app.reviewAvailabilityRevision
        return ReviewQueue.session(in: filtered)
    }

    private var reviewLabel: String {
        filtered.isEmpty && !words.isEmpty ? "No matching cards" : ReviewQueue.label(for: reviewPool)
    }

    private var deckDestinations: Int {
        let levels = ["N5", "N4", "N3", "N2", "N1"].filter { level in words.contains { $0.jlpt == level } }.count
        return decks.count + levels
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    vocabHeader
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        learningProgress(at: timeline.date)
                    }

                    HStack(spacing: 10) {
                        DesignSearchField(text: $query, placeholder: "Search saved words...")
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 48, height: 48)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
                        }
                        .accessibilityLabel("Filter words")
                    }

                    if hasFilters || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack {
                            Text("\(filtered.count) of \(words.count) saved words")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear search & filters") {
                                query = ""
                                jlpt = nil
                                posFilter = .all
                                sourceChannel = nil
                            }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                        }
                    }

                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            showClipSearch = true
                        } label: {
                            Label("Find examples in clips", systemImage: "headphones")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.studyAccent)
                    }

                    OrangePillBar(items: VocabSection.allCases, selection: $section, title: \.rawValue)

                    switch section {
                    case .learn: learnSection
                    case .mine: myWordsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Color.studyPage.ignoresSafeArea())
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
        .sheet(isPresented: $showClipSearch) {
            SearchView(initialQuery: query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .sheet(isPresented: $showDeckBuilder) {
            CustomDeckBuilder()
        }
        .sheet(isPresented: $showFilters, onDismiss: {
            if buildDeckAfterFilters {
                buildDeckAfterFilters = false
                showDeckBuilder = true
            }
        }) {
            VocabFilterSheet(
                sort: $sort,
                jlpt: $jlpt,
                posFilter: $posFilter,
                sourceChannel: $sourceChannel,
                channels: channels,
                onNewDeck: { buildDeckAfterFilters = true }
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear { openPendingReviewIfNeeded() }
        .onChange(of: app.pendingDeepLink) { _, _ in openPendingReviewIfNeeded() }
    }

    /// Title, subtitle, known count, and the cheer mascot — matching the design boards.
    private var vocabHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vocab")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LearningInk.japanese)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .textGlow(LearningInk.glow, level: app.profile.glow)
                Text("Grow your vocabulary, one word at a time.")
                    .font(.subheadline)
                    .foregroundStyle(Color.studyMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !words.isEmpty {
                    Text(dueWords.isEmpty ? "Nothing due right now" : "\(dueWords.count) due")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.studyMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            JojoMascot(height: 84, floats: false, pose: .cheer)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func learningProgress(at now: Date) -> some View {
        let progress = VocabularyProgress(words: words, dailyGoal: app.profile.dailyVocabularyGoal, now: now)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(progress.learnedCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(LearningInk.japanese)
                Text(progress.learnedCount == 1 ? "word learned" : "words learned")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            Text("Marked Known by you or through reviews · \(progress.savedCount) saved")
                .font(.caption)
                .foregroundStyle(Color.studyMuted)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Today's practice")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Menu {
                    ForEach(VocabularyProgress.goalOptions, id: \.self) { goal in
                        Button {
                            Haptics.selection()
                            app.setDailyVocabularyGoal(goal)
                        } label: {
                            if progress.dailyGoal == goal {
                                Label("\(goal) words a day", systemImage: "checkmark")
                            } else {
                                Text("\(goal) words a day")
                            }
                        }
                    }
                } label: {
                    Label("Goal: \(progress.dailyGoal)", systemImage: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.studyAccent)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Daily vocabulary target, \(progress.dailyGoal) words")
            }

            HStack {
                Text("\(progress.practicedToday) / \(progress.dailyGoal) words")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 8)
                Text(progress.goalReached ? "Goal reached" : "\(progress.remaining) to go")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(progress.goalReached ? LearningInk.spoken : Color.studyMuted)
            }

            ProgressView(value: progress.fraction)
                .tint(progress.goalReached ? LearningInk.spoken : Color.studyAccent)
                .accessibilityLabel("Daily vocabulary practice")
                .accessibilityValue("\(progress.practicedToday) of \(progress.dailyGoal) words practiced today")

            Text("Review or rate a word to count it. Each word counts once a day.")
                .font(.caption)
                .foregroundStyle(Color.studyMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.cardStroke, lineWidth: 1)
        }
    }

    private var learnSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if words.isEmpty {
                emptyVocab
            } else {
                Button {
                    startReview(reviewPool, title: "Review")
                } label: {
                    Text(reviewLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.sakuraButton, in: Capsule())
                }
                .buttonStyle(ChunkyPressStyle())
                .disabled(reviewPool.isEmpty)
                .coachTarget(.vocabReview)
                .task(id: reviewPool.map(\.key)) {
                    guard !reviewPool.isEmpty else {
                        GuidanceCenter.shared.withdrawTip(.vocabReview)
                        return
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    GuidanceCenter.shared.requestTip(.vocabReview)
                }
                .onDisappear { GuidanceCenter.shared.withdrawTip(.vocabReview) }
                Button {
                    Haptics.selection()
                    section = .mine
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.studyAccent)
                            .frame(width: 28)
                        Text("Decks")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text("\(deckDestinations)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.studyMuted)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
                }
                .buttonStyle(.plain)
                Text(hasFilters || !query.isEmpty ? "Matching words" : "All Vocabulary")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if filtered.isEmpty {
                    Text("No words match this search.")
                        .font(.subheadline)
                        .foregroundStyle(Color.studyMuted)
                        .lineLimit(2)
                } else {
                    wordList(filtered)
                }
                if !hasFilters && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reviewPool.isEmpty {
                    DisclosureGroup("Focus practice") {
                        if let next = reviewPool.first {
                            todaysFocusCard(next).padding(.top, 8)
                        }
                        WeakWordRadarView(pockets: app.weakWordPockets()) { pocket in
                            startReviewKeys(pocket.keys, title: pocket.title)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            DisclosureGroup("How words become familiar") {
                Text("Example only. Your words progress through reviews and the familiarity marks you choose.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 8)
                RipenTimelineView()
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    /// The next card from the actual due or early-practice queue.
    private func todaysFocusCard(_ word: SavedWord) -> some View {
        let gloss = word.displayDefinitions(mode: app.profile.dictionary).first ?? word.gloss
        let total = max(reviewPool.count, 1)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's focus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.studyAccent)
                HStack(spacing: 8) {
                    Text(word.surface)
                        .font(JojoFont.jp(36, bold: true, relativeTo: .largeTitle))
                        .foregroundStyle(LearningInk.japanese)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textGlow(LearningInk.glow, level: app.profile.glow)
                    Button {
                        SpeechService.shared.speak(word.surface)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Color.studyAccent)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Play \(word.surface)")
                }
                if app.profile.showRomaji, !word.romaji.isEmpty {
                    Text(word.romaji)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.studyMuted)
                        .lineLimit(1)
                }
                Text(gloss)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(total) \(total == 1 ? "card" : "cards") in this session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.studyMuted)
            }
            Spacer(minLength: 4)
            JojoMascot(height: 96, floats: false, pose: .peek)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Color.studyFocus, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.sakuraPink.opacity(app.profile.glow == .off ? 0.28 : 0.7), lineWidth: 1.4)
        )
        .chromeGlow(Color.sakuraPink, level: app.profile.glow, radius: 12)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's focus, \(word.surface), \(gloss)")
    }

    private var myWordsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            decksSection
            if words.isEmpty {
                emptyVocab
            } else if filtered.isEmpty {
                Text("No words match this search or filter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                wordList(filtered)
            }
        }
    }

    private func wordList(_ words: [SavedWord]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(words, id: \.key) { word in
                VocabStatusRow(word: word)
            }
        }
    }

    private var emptyVocab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your words will collect here")
                    .font(.headline)
                Text("There's no save button. Every word you look up becomes a flashcard on its own.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                emptyStep(1, "Watch a clip in the feed.")
                emptyStep(2, "Turn on Tap Words in the player, then tap a Japanese word.")
                emptyStep(3, "Come back here to review it before you forget.")
            }
            Button {
                Haptics.selection()
                app.pendingDeepLink = .feed
            } label: {
                Text("Find your first word")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.sakuraButton, in: Capsule())
            }
            .buttonStyle(ChunkyPressStyle())
            .accessibilityHint("Opens the feed")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
    }

    private func emptyStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.sakuraButton, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
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
                        DeckRow(title: deck.name, subtitle: "\(matching.count) words · \(deck.filterKind == "channel" ? "Channel" : "Topic")", symbol: deck.filterKind == "channel" ? "person.crop.square" : "square.grid.2x2")
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
                ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { level in
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
        query = ""
        jlpt = nil
        posFilter = .all
        sourceChannel = nil
        let pool = ReviewQueue.session(in: words)
        startReview(pool, title: ReviewQueue.label(for: pool))
    }

    private func deckWords(_ deck: CustomDeck) -> [SavedWord] {
        words.filter { word in
            guard let clip = app.clip(id: word.contextClipId) else { return false }
            return deck.filterKind == "channel" ? clip.channelName == deck.filterValue : clip.category == deck.filterValue
        }
    }

    private func startReview(_ source: [SavedWord], title: String) {
        startReviewKeys(Array(source.prefix(10).map(\.key)), title: title)
    }

    private func startReviewKeys(_ keys: [String], title: String) {
        let capped = Array(keys.prefix(10))
        guard !capped.isEmpty else { return }
        Haptics.medium()
        reviewSession = ReviewSessionConfig(title: title, keys: capped)
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

    @Query private var words: [SavedWord]
    private var channels: [String] {
        Array(Set(words.compactMap { app.clip(id: $0.contextClipId)?.channelName })).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Decks group your saved words by source or topic. New matching words join automatically.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("By show / channel") {
                    if channels.isEmpty {
                        Text("Look up words in a clip to create a deck from its channel.")
                            .foregroundStyle(.secondary)
                    }
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
        let existing = (try? app.context.fetch(FetchDescriptor<CustomDeck>())) ?? []
        guard !existing.contains(where: { $0.filterKind == kind && $0.filterValue == value }) else {
            dismiss()
            return
        }
        app.context.insert(CustomDeck(name: name, filterKind: kind, filterValue: value))
        app.save()
        Haptics.success()
        dismiss()
    }
}

/// Known words wear a check. Every other word shows how many times it has been met.
struct VocabStatusRow: View {
    let word: SavedWord
    @Environment(AppModel.self) private var app

    private var gloss: String {
        word.displayDefinitions(mode: app.profile.dictionary).first ?? word.gloss
    }

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: word.key) {
                HStack(spacing: 12) {
                    Group {
                        if word.state == .known {
                            Image(systemName: "checkmark")
                        } else {
                            Text("\(word.occurrenceCount)").monospacedDigit()
                        }
                    }
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(word.state == .known ? Color.spokenGreen : Color.studyAccent, in: Circle())
                    .accessibilityLabel(word.state == .known ? "Known" : "Met \(word.occurrenceCount) times")
                    VStack(alignment: .leading, spacing: 2) {
                        if app.profile.showFurigana, !word.primaryReading.isEmpty, word.primaryReading != word.surface {
                            Text(word.primaryReading).font(JojoFont.jp(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                        Text(word.surface).font(JojoFont.jp(20, bold: true, relativeTo: .title3))
                            .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                        if app.profile.showRomaji, !word.romaji.isEmpty {
                            Text(word.romaji).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(gloss).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                SpeechService.shared.speak(word.surface)
            } label: {
                Image(systemName: "speaker.wave.2").foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Hear \(word.surface)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.cardStroke))
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
                        choice(option.rawValue, selected: sort == option) { sort = option }
                    }
                }
                Section("JLPT") {
                    choice("Any level", selected: jlpt == nil) { jlpt = nil }
                    ForEach(["N5", "N4", "N3", "N2", "N1"], id: \.self) { level in
                        choice(level, selected: jlpt == level) { jlpt = level }
                    }
                }
                Section("Word type") {
                    ForEach(StudyPosFilter.allCases) { filter in
                        choice(filter.title, selected: posFilter == filter) { posFilter = filter }
                    }
                }
                Section("Source") {
                    choice("Any source", selected: sourceChannel == nil) { sourceChannel = nil }
                    ForEach(channels, id: \.self) { channel in
                        choice(channel, selected: sourceChannel == channel) { sourceChannel = channel }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        sort = .recent
                        jlpt = nil
                        posFilter = .all
                        sourceChannel = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.studyAccent) }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

}

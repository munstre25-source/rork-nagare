import SwiftUI
import SwiftData

/// Full-screen scripted product showcase for screen-recording a Jojo marketing clip.
/// Silent arc (add captions in edit): anime feed → tap → scroll to Minecraft → flashcard.
struct MarketingShowcaseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .prep
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var feedClips: [Clip] = []
    @State private var currentId: String?
    @State private var showFlashcard: Bool = false
    @State private var flashWord: SavedWord?
    @State private var scriptTask: Task<Void, Never>?
    @State private var countdown: Int?

    private enum Phase {
        case prep, running, done
    }

    var body: some View {
        ZStack {
            Color.bgPlayer.ignoresSafeArea()
            switch phase {
            case .prep:
                prepScreen
            case .running:
                showcaseStage
            case .done:
                doneScreen
            }
        }
        .environment(coordinator)
        .environment(lookup)
        .environment(\.colorScheme, .dark)
        .statusBarHidden(phase == .running)
        .onDisappear {
            scriptTask?.cancel()
            coordinator.stop()
            lookup.dismiss()
        }
        .onChange(of: currentId) { _, newId in
            guard phase == .running, !showFlashcard,
                  let newId, let clip = feedClips.first(where: { $0.id == newId }) else { return }
            coordinator.activate(clip, startLine: 0, loopLine: true)
        }
    }

    // MARK: Prep

    private var prepScreen: some View {
        VStack(spacing: Spacing.l) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            Spacer()
            Image(systemName: "record.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.jojoOrange)
            Text("Marketing demo script")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Start a screen recording, then tap Begin. Silent walkthrough — anime clip, word tap, scroll to Minecraft, then a flashcard. Add your own captions in edit.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
            VStack(alignment: .leading, spacing: 8) {
                scriptBeatRow("1", "Anime clip plays in For You")
                scriptBeatRow("2", "Word lookup pops open")
                scriptBeatRow("3", "Feed scrolls to Minecraft")
                scriptBeatRow("4", "Flashcard with context clip")
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Spacing.l)
            Spacer()
            Button {
                Haptics.medium()
                beginShowcase()
            } label: {
                Label("Begin showcase", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
    }

    private func scriptBeatRow(_ n: String, _ text: String) -> some View {
        HStack(spacing: Spacing.m) {
            Text(n)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Color.jojoOrange, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Running stage

    private var showcaseStage: some View {
        ZStack {
            if showFlashcard, let flashWord {
                flashcardBeat(flashWord)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                feedPager
            }

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private var feedPager: some View {
        VStack(spacing: 0) {
            HStack {
                Text("For You")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Explore")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 8)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(feedClips) { clip in
                        ClipStageView(
                            clip: clip,
                            immersiveFeed: true,
                            onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) }
                        )
                        .containerRelativeFrame(.vertical)
                        .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentId)
            .scrollDisabled(true)
        }
    }

    private func flashcardBeat(_ word: SavedWord) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
                GeometryReader { proxy in
                    Capsule().fill(Color.jojoOrange)
                        .frame(width: proxy.size.width * 0.18, height: 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .frame(height: 6)
                Text("1/6")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.s)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    WordHeaderCard(
                        surface: word.surface,
                        readings: word.readings,
                        romaji: word.romaji,
                        pos: word.pos,
                        conjugationClass: word.conjugationClass,
                        jlpt: word.jlpt,
                        showFurigana: true,
                        showRomaji: true
                    )
                    .environment(\.colorScheme, .dark)

                    Text("Definitions")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.55))
                    ForEach(Array(word.definitions.prefix(2).enumerated()), id: \.offset) { i, def in
                        DefinitionRow(number: i + 1, tag: word.pos, text: def, dark: true)
                    }
                    if !word.contextSentence.isEmpty {
                        Text("Context")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.55))
                        HighlightedSentence(
                            sentence: word.contextSentence,
                            target: word.contextSurface.isEmpty ? word.surface : word.contextSurface,
                            size: 19,
                            baseColor: .white
                        )
                        .padding(Spacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        if let clip = app.clip(id: word.contextClipId) {
                            ClipThumbnailButton(clip: clip, emphasizesPlay: true) {}
                                .disabled(true)
                        }
                    }
                }
                .padding(Spacing.l)
            }

            HStack(spacing: Spacing.m) {
                answerChip(title: "Again", subtitle: "<1m", color: .againBackground, fg: .againText)
                answerChip(title: "Good", subtitle: "<10m", color: .goodBackground, fg: .goodText)
            }
            .padding(Spacing.l)
        }
        .background(Color.bgPlayer.ignoresSafeArea())
    }

    private func answerChip(title: String, subtitle: String, color: Color, fg: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.headline.weight(.bold))
            Text(subtitle).font(.caption.weight(.semibold))
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Done

    private var doneScreen: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.jojoOrange)
            Text("Showcase finished")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Stop your screen recording, then trim the countdown if you want.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
            Button("Run again") {
                phase = .prep
                resetShowcaseState()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Spacing.l)
            Button("Done") { dismiss() }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
                .frame(minHeight: 48)
                .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: Script

    /// Anime first, then Minecraft — both local demo clips when available.
    private func demoFeedClips() -> [Clip] {
        let preferredIds = ["hoshizora-academy-07", "boss-rush-live-09"]
        var ordered: [Clip] = []
        for id in preferredIds {
            if let clip = app.clip(id: id), clip.hasLocalVideo || clip.hasPlayableVideo {
                ordered.append(clip)
            }
        }
        if ordered.count < 2 {
            for clip in app.clips where clip.hasLocalVideo && !ordered.contains(where: { $0.id == clip.id }) {
                ordered.append(clip)
                if ordered.count >= 2 { break }
            }
        }
        if ordered.isEmpty, let fallback = app.recommendedClip(preferShort: true) ?? app.clips.first {
            ordered = [fallback]
        }
        return ordered
    }

    private func beginShowcase() {
        lookup.offlineOnly = true
        let clips = demoFeedClips()
        feedClips = clips
        guard let first = clips.first else {
            phase = .done
            return
        }
        currentId = first.id
        app.markVocabSaveCoachSeen()
        phase = .running
        track("marketing_showcase_started", props: [
            "clips": clips.map(\.id).joined(separator: ","),
        ])
        scriptTask?.cancel()
        scriptTask = Task { @MainActor in
            for n in [3, 2, 1] {
                withAnimation(.snappy) { countdown = n }
                Haptics.selection()
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
            }
            withAnimation { countdown = nil }

            // Beat 1 — anime (or first) plays
            coordinator.activate(first, startLine: 0, loopLine: true)
            try? await Task.sleep(for: .milliseconds(2800))
            guard !Task.isCancelled else { return }

            // Beat 2 — tap a word on the first clip
            var savedFromTap: SavedWord?
            if let line = first.lines.first,
               let idx = line.tokens.firstIndex(where: { $0.containsKanji && $0.tappable })
                ?? line.tokens.firstIndex(where: \.tappable) {
                let token = line.tokens[idx]
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    lookup.select(token: token, tokenIndex: idx, lineIndex: 0, clip: first, app: app)
                }
                try? await Task.sleep(for: .milliseconds(2800))
                guard !Task.isCancelled else { return }
                let key = AppModel.wordKey(for: token)
                savedFromTap = (try? app.context.fetch(
                    FetchDescriptor<SavedWord>(predicate: #Predicate { $0.key == key })
                ))?.first
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    lookup.dismiss()
                }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
            }

            // Beat 3 — scroll to Minecraft (second clip), like a real For You swipe
            if let second = clips.dropFirst().first {
                withAnimation(.easeInOut(duration: 0.55)) {
                    currentId = second.id
                }
                // onChange activates playback; give the page settle + watch time
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                coordinator.activate(second, startLine: 0, loopLine: true)
                try? await Task.sleep(for: .milliseconds(3200))
                guard !Task.isCancelled else { return }
            }

            // Beat 4 — flashcard from the tapped word (real poster if bundled)
            if let word = savedFromTap {
                flashWord = word
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    showFlashcard = true
                }
                try? await Task.sleep(for: .milliseconds(3400))
            }

            guard !Task.isCancelled else { return }
            coordinator.stop()
            withAnimation(.easeInOut(duration: 0.35)) { phase = .done }
            track("marketing_showcase_finished")
        }
    }

    private func resetShowcaseState() {
        scriptTask?.cancel()
        coordinator.stop()
        lookup.dismiss()
        showFlashcard = false
        flashWord = nil
        countdown = nil
        feedClips = []
        currentId = nil
    }
}

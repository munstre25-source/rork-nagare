import SwiftUI
import SwiftData

/// Full-screen scripted product showcase for screen-recording a Jojo marketing clip.
/// Story arc mirrors common JP-learning short demos: scroll → tap word → flashcard.
struct MarketingShowcaseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .prep
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var clip: Clip?
    @State private var callout: String?
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
                .foregroundStyle(Color.nagareOrange)
            Text("Marketing demo script")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Start a screen recording on your device, then tap Begin. Jojo will autoplay a ~15s scroll → tap → flashcard sequence.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.l)
            VStack(alignment: .leading, spacing: 8) {
                scriptBeatRow("1", "Feed scrolls & karaoke plays")
                scriptBeatRow("2", "Word lookup pops open")
                scriptBeatRow("3", "Flashcard with context clip")
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
                .background(Color.nagareOrange, in: Circle())
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
            } else if let clip {
                feedBeat(clip)
            }

            if let callout {
                Text(callout)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    .padding(.horizontal, Spacing.l)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .allowsHitTesting(false)
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

    private func feedBeat(_ clip: Clip) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("For You")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 8)

            ClipStageView(
                clip: clip,
                videoAspect: 16 / 9,
                onlyCurrentLine: true,
                showsRail: true,
                immersiveFeed: true,
                onActivate: {}
            )
            .frame(maxHeight: .infinity)
        }
    }

    private func flashcardBeat(_ word: SavedWord) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
                GeometryReader { proxy in
                    Capsule().fill(Color.nagareOrange)
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
                            ClipThumbnailButton(clip: clip) {}
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
                .foregroundStyle(Color.nagareOrange)
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

    private func beginShowcase() {
        lookup.offlineOnly = true
        let chosen = app.recommendedClip(preferShort: true) ?? app.clips.first
        clip = chosen
        guard let chosen else {
            phase = .done
            return
        }
        phase = .running
        track("marketing_showcase_started", props: ["clip": chosen.id])
        scriptTask?.cancel()
        scriptTask = Task { @MainActor in
            // Countdown so you can start the OS screen recorder.
            for n in [3, 2, 1] {
                withAnimation(.snappy) { countdown = n }
                Haptics.selection()
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
            }
            withAnimation { countdown = nil }

            coordinator.activate(chosen, startLine: 0, loopLine: true)

            // Beat 1 — doomscroll / feed
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                callout = "Learn by doomscrolling instead 🥰"
            }
            try? await Task.sleep(for: .milliseconds(2800))
            guard !Task.isCancelled else { return }
            withAnimation { callout = nil }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            // Beat 2 — tap to look up
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                callout = "tap to look up words you don't know…"
            }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }

            if let line = chosen.lines.first,
               let idx = line.tokens.firstIndex(where: { $0.containsKanji && $0.tappable })
                ?? line.tokens.firstIndex(where: \.tappable) {
                let token = line.tokens[idx]
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    lookup.select(token: token, tokenIndex: idx, lineIndex: 0, clip: chosen, app: app)
                }
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation { callout = nil }
                try? await Task.sleep(for: .milliseconds(2200))
                guard !Task.isCancelled else { return }

                // Beat 3 — flashcards created
                let key = AppModel.wordKey(for: token)
                flashWord = (try? app.context.fetch(
                    FetchDescriptor<SavedWord>(predicate: #Predicate { $0.key == key })
                ))?.first
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    lookup.dismiss()
                    showFlashcard = true
                    callout = "and flashcards are created for you!"
                }
                try? await Task.sleep(for: .milliseconds(2800))
                withAnimation { callout = nil }
                try? await Task.sleep(for: .milliseconds(1800))
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
        callout = nil
        showFlashcard = false
        flashWord = nil
        countdown = nil
        clip = nil
    }
}

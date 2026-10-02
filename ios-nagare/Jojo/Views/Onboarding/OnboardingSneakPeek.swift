import SwiftUI
import SwiftData

/// Phone-framed live demo of the real feed during onboarding. Muted by default,
/// non-interactive so it cannot pollute the learner's vocab deck.
struct OnboardingSneakPeek: View {
    var isActive: Bool = true

    @Environment(AppModel.self) private var app
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var feedClips: [Clip] = []
    @State private var currentId: String?
    @State private var showFlashcard: Bool = false
    @State private var flashSurface: String = "嘘"
    @State private var caption: String = "Watch real Japanese"
    @State private var scriptTask: Task<Void, Never>?
    @State private var unmuted: Bool = false
    @State private var showMockPopup: Bool = false
    @State private var pulseToken: Int? = nil
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .center, spacing: Spacing.m) {
                phoneFrame
                    .frame(maxWidth: 220)
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(caption)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.35), value: caption)
                    Text("Same scroll.\nBigger dreams.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sakuraPink)
                    Spacer(minLength: 0)
                    Button {
                        unmuted.toggle()
                        if unmuted && coordinator.isMuted {
                            coordinator.toggleMute()
                        } else if !unmuted && !coordinator.isMuted {
                            coordinator.toggleMute()
                        }
                    } label: {
                        Label(unmuted ? "Mute" : "Tap to unmute", systemImage: unmuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            JojoMascot(height: 90, pose: .peek)
                .offset(x: 18, y: 12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .environment(coordinator)
        .environment(lookup)
        .onAppear {
            lookup.offlineOnly = true
            lookup.previewOnly = true
            if !coordinator.isMuted {
                coordinator.toggleMute()
            }
            prepareClips()
            if isActive { startLoop() }
        }
        .onChange(of: isActive) { _, active in
            if active {
                startLoop()
            } else {
                scriptTask?.cancel()
                coordinator.pause()
                showMockPopup = false
                showFlashcard = false
                isPulsing = false
                pulseToken = nil
            }
        }
        .onDisappear {
            scriptTask?.cancel()
            coordinator.stop()
        }
        .onChange(of: currentId) { _, newId in
            guard !showFlashcard,
                  let newId, let clip = feedClips.first(where: { $0.id == newId }) else { return }
            coordinator.activate(clip, startLine: 0, loopLine: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sneak peek of the Jojo feed")
    }

    private var phoneFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 72, height: 18)
                    .padding(.top, 10)
                    .overlay {
                        Capsule().fill(Color.white.opacity(0.12)).frame(width: 72, height: 18).padding(.top, 10)
                    }
                ZStack {
                    if showFlashcard {
                        sneakFlashcard
                            .transition(.asymmetric(
                                insertion: .modifier(active: SneakFlip(angle: -90), identity: SneakFlip(angle: 0)).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else {
                        feedPager
                        if showMockPopup {
                            Color.black.opacity(0.18)
                            MockPopupCard()
                                .scaleEffect(0.72)
                                .padding(.horizontal, 8)
                                .transition(.scale(scale: 0.94).combined(with: .opacity))
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .aspectRatio(9 / 17, contentMode: .fit)
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .allowsHitTesting(false)
    }

    private var feedPager: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(feedClips) { clip in
                        ClipStageView(
                            clip: clip,
                            pulseTokenIndex: clip.id == currentId ? pulseToken : nil,
                            isPulsing: clip.id == currentId && isPulsing,
                            showsChannelRow: false,
                            immersiveFeed: true,
                            onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) }
                        )
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                        .background(Color.bgPlayer)
                        .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentId)
            .scrollDisabled(true)
        }
        .background(Color.bgPlayer)
    }

    private var sneakFlashcard: some View {
        VStack(spacing: Spacing.m) {
            Text(flashSurface)
                .font(JojoFont.jp(36, bold: true))
                .foregroundStyle(.white)
            Text("Tap to reveal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
            HStack(spacing: Spacing.s) {
                Text("Again")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.againText)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.againBackground, in: RoundedRectangle(cornerRadius: 12))
                Text("Good")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.goodBackground, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPlayer)
    }

    private func prepareClips() {
        let preferred = ["hoshizora-academy-07", "boss-rush-live-09"]
        var ordered: [Clip] = []
        for id in preferred {
            if let clip = app.clip(id: id) { ordered.append(clip) }
        }
        if ordered.isEmpty {
            ordered = Array(app.clips.prefix(2))
        }
        feedClips = ordered
        currentId = ordered.first?.id
    }

    private func startLoop() {
        scriptTask?.cancel()
        guard let first = feedClips.first else { return }
        scriptTask = Task { @MainActor in
            while !Task.isCancelled {
                // Beat 1 — play
                showFlashcard = false
                showMockPopup = false
                isPulsing = false
                pulseToken = nil
                caption = "Watch real Japanese"
                currentId = first.id
                coordinator.activate(first, startLine: 0, loopLine: true)
                try? await Task.sleep(for: .milliseconds(2600))
                guard !Task.isCancelled else { return }

                // Beat 2 — visual word tap (no vocab write)
                caption = "Tap any word"
                if let line = first.lines.first {
                    let idx = line.tokens.firstIndex(where: { $0.surface.contains("嘘") })
                        ?? line.tokens.firstIndex(where: { $0.containsKanji && $0.tappable })
                        ?? line.tokens.firstIndex(where: \.tappable)
                    if let idx {
                        let token = line.tokens[idx]
                        flashSurface = token.surface
                        pulseToken = idx
                        isPulsing = true
                        withAnimation(Motion.popupSpring) { showMockPopup = true }
                        try? await Task.sleep(for: .milliseconds(2400))
                        guard !Task.isCancelled else { return }
                        withAnimation(Motion.popupSpring) { showMockPopup = false }
                        isPulsing = false
                        pulseToken = nil
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                }

                // Beat 3 — swipe to second clip
                if let second = feedClips.dropFirst().first {
                    caption = "Keep scrolling"
                    withAnimation(.easeInOut(duration: 0.5)) { currentId = second.id }
                    try? await Task.sleep(for: .milliseconds(2800))
                    guard !Task.isCancelled else { return }
                }

                // Beat 4 — flashcard
                caption = "Flashcards build themselves"
                withAnimation(Motion.cardFlip) { showFlashcard = true }
                try? await Task.sleep(for: .milliseconds(2600))
                guard !Task.isCancelled else { return }
                withAnimation { showFlashcard = false }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }
}

private struct SneakFlip: ViewModifier {
    var angle: Double
    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
    }
}

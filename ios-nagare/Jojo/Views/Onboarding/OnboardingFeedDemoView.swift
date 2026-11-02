import SwiftUI

/// Full-screen feed the learner can scroll and tap before we ask for a review.
/// Same player, transcript, and dictionary card as For You. Continue unlocks after the first word tap.
struct OnboardingFeedDemoView: View {
    let onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var clips: [Clip] = []
    @State private var currentId: String?
    @State private var videoExpanded: Bool = false
    @State private var showsTheaterControls = false
    @State private var theaterOptionsPresented = false
    @State private var didOpenDictionary: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            hint
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(clips) { clip in
                                ClipStageView(
                                    clip: clip,
                                    showsChannelRow: true,
                                    immersiveFeed: true,
                                    videoExpanded: videoExpanded,
                                    showsTheaterControls: showsTheaterControls,
                                    onTheaterPresentationChange: { theaterOptionsPresented = $0 },
                                    onToggleVideoSize: {
                                        Haptics.selection()
                                        videoExpanded.toggle()
                                    },
                            onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) },
                            onFullscreen: nil,
                            onSkip: { skipClip() }
                        )
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                                .clipped()
                                .id(clip.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(SingleClipPerSwipeBehavior())
                    .scrollPosition(id: $currentId, anchor: .top)
                    .scrollDisabled(lookup.isPresented)
                    .clipped()
                    .onChange(of: geo.size) { _, _ in
                        guard let id = currentId else { return }
                        Task { @MainActor in
                            await Task.yield()
                            guard currentId == id else { return }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { proxy.scrollTo(id, anchor: .top) }
                        }
                    }
                }
            }
            if didOpenDictionary, lookup.selection == nil {
                Button("Continue") {
                    Haptics.medium()
                    onContinue()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.watchBackground.ignoresSafeArea())
        .environment(coordinator)
        .environment(lookup)
        .modifier(TheaterChromeModifier(
            expanded: videoExpanded,
            visible: $showsTheaterControls,
            playing: coordinator.player?.isPlaying == true,
            blocked: lookup.isPresented || theaterOptionsPresented
        ))
        .environment(\.colorScheme, .dark)
        .onAppear(perform: start)
        .onDisappear { coordinator.stop() }
        .onChange(of: currentId) { _, id in
            guard let id, let clip = clips.first(where: { $0.id == id }) else { return }
            coordinator.activate(clip, startLine: 0, loopLine: true)
        }
        .onChange(of: lookup.selection?.token.surface) { _, surface in
            if surface != nil { didOpenDictionary = true }
        }
    }

    private var hint: some View {
        HStack(spacing: Spacing.s) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.translationText)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Back")
            }
            Text(didOpenDictionary ? "That's the dictionary. Scroll for another clip, or continue." : "Scroll the feed, then tap any word.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.translationText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xs)
    }

    /// Plays the verified clips, so the transcript on screen is what the video says.
    private func start() {
        lookup.offlineOnly = true
        let ordered = app.showcaseClips(limit: 3)
        clips = ordered
        currentId = ordered.first?.id
        if let first = ordered.first {
            coordinator.activate(first, startLine: 0, loopLine: true)
        }
    }

    private func skipClip() {
        guard let id = currentId, let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let next = clips.indices.contains(index + 1) ? clips[index + 1] : clips.first
        currentId = next?.id
    }
}

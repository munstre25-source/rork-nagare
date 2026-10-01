import SwiftUI
import AVKit

/// Post-splash gate: clear Play / Skip before onboarding.
struct LaunchDemoGateView: View {
    let onPlay: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            JojoLogo(drawProgress: 1, size: 0.85)
                .padding(.bottom, Spacing.xl)
            Spacer()
            VStack(spacing: Spacing.m) {
                Button {
                    Haptics.medium()
                    onPlay()
                } label: {
                    Label("Play app demo", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    Haptics.selection()
                    onSkip()
                } label: {
                    Text("Skip")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Skip app demo")
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-screen product demo: bundled `MarketingDemo.mp4` if present, otherwise a live in-app reel.
/// No marketing text overlays — only Skip chrome.
struct AppMarketingDemoView: View {
    let onFinished: () -> Void

    private var bundledVideoURL: URL? {
        Bundle.main.url(forResource: "MarketingDemo", withExtension: "mp4")
            ?? Bundle.main.url(forResource: "MarketingDemo", withExtension: "mov")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let url = bundledVideoURL {
                BundledMarketingPlayer(url: url, onFinished: onFinished)
            } else {
                LiveAppDemoReel(onFinished: onFinished)
            }
            skipButton
        }
        .background(Color.bgPlayer.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear { track("launch_demo_play") }
    }

    private var skipButton: some View {
        Button {
            Haptics.selection()
            track("launch_demo_skip_during")
            onFinished()
        } label: {
            Text("Skip")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(.black.opacity(0.45), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        }
        .padding(.top, Spacing.m)
        .padding(.trailing, Spacing.l)
        .accessibilityLabel("Skip demo")
    }
}

// MARK: - Bundled video

private struct BundledMarketingPlayer: View {
    let url: URL
    let onFinished: () -> Void
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        VideoPlayer(player: player)
            .disabled(true)
            .ignoresSafeArea()
            .onAppear {
                let item = AVPlayerItem(url: url)
                let av = AVPlayer(playerItem: item)
                av.isMuted = false
                player = av
                av.play()
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { _ in
                    onFinished()
                }
            }
            .onDisappear {
                if let endObserver {
                    NotificationCenter.default.removeObserver(endObserver)
                }
                endObserver = nil
                player?.pause()
                player = nil
            }
    }
}

// MARK: - Live reel (app in use, no copy overlays)

/// Scripted walkthrough of core product moments using real feed UI.
private struct LiveAppDemoReel: View {
    let onFinished: () -> Void
    @Environment(AppModel.self) private var app

    @State private var coordinator = PlaybackCoordinator()
    @State private var lookup = WordLookupController()
    @State private var clip: Clip?
    @State private var beat: Int = 0
    @State private var saveBurst: Bool = false
    @State private var holdBanner: Bool = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.bgPlayer.ignoresSafeArea()
            if let clip {
                VStack(spacing: 0) {
                    // Fake status / feed chrome without marketing copy
                    HStack {
                        Text("For You")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.s)
                    .opacity(0.85)

                    ClipStageView(
                        clip: clip,
                        videoAspect: 16 / 9,
                        onlyCurrentLine: beat < 4,
                        pulseTokenIndex: nil,
                        isPulsing: false,
                        tooltip: nil,
                        showsRail: beat >= 3,
                        immersiveFeed: true,
                        onActivate: { coordinator.activate(clip, startLine: 0, loopLine: true) }
                    )
                    .frame(maxHeight: .infinity)
                }
                .safeAreaPadding(.top, 28)
            }

            if saveBurst {
                Image(systemName: "sparkles")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.jojoOrange)
                    .shadow(color: .black.opacity(0.5), radius: 16)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
            if holdBanner {
                VStack {
                    Spacer()
                    Label("0.75×", systemImage: "tortoise.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .environment(coordinator)
        .environment(lookup)
        .allowsHitTesting(false) // watch-only reel
        .onAppear(perform: start)
        .onDisappear {
            task?.cancel()
            coordinator.stop()
            lookup.dismiss()
        }
    }

    private func start() {
        lookup.offlineOnly = true
        let chosen = app.recommendedClip(preferShort: true) ?? app.clips.first
        clip = chosen
        guard let chosen else {
            onFinished()
            return
        }
        coordinator.activate(chosen, startLine: 0, loopLine: true)
        task = Task { @MainActor in
            // Beat 0: watch karaoke (~2.5s)
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }

            // Beat 1: tap a word → dictionary popup
            if let line = chosen.lines.first,
               let idx = line.tokens.firstIndex(where: { $0.containsKanji && $0.tappable })
                ?? line.tokens.firstIndex(where: \.tappable) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    lookup.select(token: line.tokens[idx], tokenIndex: idx, lineIndex: 0, clip: chosen, app: app)
                }
                beat = 1
            }
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled else { return }

            // Beat 2: flashcard tab
            withAnimation(.snappy) { lookup.tab = .flashcard }
            beat = 2
            try? await Task.sleep(for: .milliseconds(2000))
            guard !Task.isCancelled else { return }

            // Beat 3: dismiss popup, show rail, double-tap save burst
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { lookup.dismiss() }
            coordinator.resumeAfterPopupIfNeeded()
            beat = 3
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            _ = app.saveLine(clip: chosen, lineIndex: 0)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { saveBurst = true }
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation { saveBurst = false }
            guard !Task.isCancelled else { return }

            // Beat 4: hold-to-slow
            beat = 4
            coordinator.beginHoldSlow()
            withAnimation { holdBanner = true }
            try? await Task.sleep(for: .milliseconds(1800))
            coordinator.endHoldSlow()
            withAnimation { holdBanner = false }
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .milliseconds(700))
            onFinished()
        }
    }
}

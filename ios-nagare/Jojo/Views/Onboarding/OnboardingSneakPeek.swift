#if DEBUG
import SwiftUI
import SwiftData

/// Phone-framed still of the feed. Clips do not play here; playback starts only after the paywall.
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
            prepareClips()
        }
        .onDisappear {
            coordinator.stop()
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
                            onActivate: {}
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
        let ordered = app.showcaseClips(limit: 2)
        feedClips = ordered
        currentId = ordered.first?.id
    }
}

private struct SneakFlip: ViewModifier {
    var angle: Double
    func body(content: Content) -> some View {
        content.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
    }
}
#endif

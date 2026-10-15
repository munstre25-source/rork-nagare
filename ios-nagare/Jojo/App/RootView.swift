import SwiftUI
import SwiftData

/// Routes to onboarding/paywall until onboarding is complete AND the entitlement is active.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            if !app.profile.onboardingCompleted {
                OnboardingFlowView()
                    .transition(.opacity)
            } else if !app.purchases.isSubscribed {
                // Returning user whose subscription lapsed: hard paywall, no tabs.
                ZStack {
                    JojoBrandBackground(scene: .templeDusk, showsHills: false)
                    PaywallView(allowsDebugBypass: DebugFlags.allowPaywallBypass) {}
                        .frame(maxWidth: 560)
                }
                .environment(\.brandSurface, .night)
                .environment(\.colorScheme, .dark)
                .transition(.opacity)
            } else {
                MainTabView()
                    .id("\(app.profile.accentTheme)-\(app.profile.appearanceMode)-\(app.paletteEpoch)")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: app.profile.onboardingCompleted)
        .animation(.easeInOut(duration: 0.4), value: app.purchases.isSubscribed)
    }
}

nonisolated enum AppTab: Hashable, Sendable {
    case library, feed, vocab, explore, profile
}

/// Vocab, Feed, and Profile sit in the bottom bar. Explore opens from the top switch.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .feed
    @State private var showFeedbackPrompt = false
    @State private var showManualFeedback = false
    @State private var showCancellationSurvey = false
    @Query private var savedWords: [SavedWord]
    @State private var showingExplore = false
    @State private var welcome: (due: Int, streak: Int)?

    /// True only on For You, once the learner has settled into a playing clip.
    private var focusCapsuleHidden: Bool {
        app.feedChromeHidden && tab == .feed && !showingExplore
    }

    /// The badge is a real Vocab notification: cards the learner can review now.
    /// It deliberately survives visiting Vocab and clears only as the cards are rescheduled.
    private var dueVocabNotificationCount: Int {
        savedWords.reduce(into: 0) { count, word in
            if word.state != .known, word.dueAt <= Date() {
                count += 1
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            FeedTab(
                showingExplore: $showingExplore,
                feedActive: tab == .feed
            )
            .toolbar(.hidden, for: .tabBar)
            .background(SystemTabBarHider())
            .tabItem { Label("Feed", systemImage: "play.circle") }
            .tag(AppTab.feed)

            VocabView()
                .toolbar(.hidden, for: .tabBar)
                .background(SystemTabBarHider())
                .tabItem { Label("Vocab", systemImage: "book") }
                .tag(AppTab.vocab)

            ProfileView(onGiveFeedback: { showManualFeedback = true })
                .toolbar(.hidden, for: .tabBar)
                .background(SystemTabBarHider())
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppTab.profile)
        }
        .tint(Color.designOrange)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // While a clip is playing the whole dock leaves the screen so the raised
            // panda never covers the video. It returns on tap, pause, or a dictionary card.
            if !app.hidesMainTabBar, !focusCapsuleHidden {
                JojoDock(selection: $tab, vocabBadge: dueVocabNotificationCount)
                    .padding(.horizontal, 26)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: focusCapsuleHidden)
        .preferredColorScheme(app.profile.scheme.colorScheme)
        .onAppear { JojoPalette.activate(theme: app.profile.theme, scheme: app.profile.scheme) }
        .onChange(of: tab) { _, newTab in
            if newTab != .feed {
                showingExplore = false
                app.feedChromeHidden = false
            }
        }
        .onChange(of: app.pendingFeedClipId) { _, id in
            if id != nil {
                showingExplore = false
                tab = .feed
            }
        }
        .onChange(of: app.pendingDeepLink) { _, link in
            switch link {
            case .review:
                tab = .vocab
            case .feed:
                tab = .feed
                app.clearDeepLink()
            case nil:
                break
            }
        }
        .onChange(of: app.purchases.pendingCancellationSurvey) { _, pending in
            guard pending, app.shouldPresentCancellationSurvey else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showCancellationSurvey = true
            }
        }
        .overlay {
            ZStack {
                if let welcome {
                    WelcomeHomeBurst(due: welcome.due, streak: welcome.streak)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            if let home = app.claimWelcomeHome() {
                welcome = home
                Task {
                    try? await Task.sleep(for: .milliseconds(1700))
                    withAnimation(.easeOut(duration: 0.25)) { welcome = nil }
                }
            }
            if app.pendingDeepLink == .review { tab = .vocab }
            if app.pendingDeepLink == .feed { tab = .feed }
            if app.noteMainAppOpenAndShouldAskFeedback() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                    showFeedbackPrompt = true
                }
            }
            if app.shouldPresentCancellationSurvey {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showCancellationSurvey = true
                }
            }
        }
        .sheet(isPresented: $showFeedbackPrompt) {
            FeedbackFlowSheet { showFeedbackPrompt = false }
        }
        .sheet(isPresented: $showManualFeedback) {
            FeedbackBoardView()
        }
        .sheet(isPresented: $showCancellationSurvey) {
            CancellationSurveySheet { showCancellationSurvey = false }
        }
    }
}

/// The system tab bar stays in the hierarchy even when SwiftUI asks it to hide, which
/// paints a second set of labels under the custom capsule. This forces it off.
private struct SystemTabBarHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.hide() }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hide()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            hide()
        }

        func hide() {
            tabBarController?.tabBar.isHidden = true
        }
    }
}

/// For You and Explore share the Feed tab. The floating capsule is the only bottom chrome.
private struct FeedTab: View {
    @Binding var showingExplore: Bool
    var feedActive: Bool

    var body: some View {
        ZStack {
            FeedView(
                isActiveTab: feedActive && !showingExplore,
                onOpenExplore: { showingExplore = true }
            )
            .opacity(showingExplore ? 0 : 1)
            .allowsHitTesting(!showingExplore)
            .accessibilityHidden(showingExplore)

            if showingExplore {
                ExploreHomeView(onOpenFeed: { showingExplore = false })
            }
        }
    }
}

/// Curved dock from the approved navigation board: Vocab, raised Feed panda, Profile.
struct JojoDock: View {
    @Binding var selection: AppTab
    var vocabBadge: Int = 0

    // The approved pastel navigation is intentionally constant across the app's looks.
    private let accent = Color(hex: "#D47BE8")
    private let muted = Color(hex: "#9290AA")
    private let fill = Color.white

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .strokeBorder(Color(hex: "#F3F1F7"), lineWidth: 1)
                }
                .shadow(color: Color(hex: "#716B91").opacity(0.16), radius: 18, y: 8)
                .frame(height: 82)

            HStack(alignment: .bottom, spacing: 0) {
                sideItem(.vocab, title: "Vocab", symbol: "book.closed")
                Spacer(minLength: 0)
                feedItem
                Spacer(minLength: 0)
                sideItem(.profile, title: "Profile", symbol: "person")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .offset(y: -25)
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.top, 31)
        .accessibilityElement(children: .contain)
    }

    private var feedItem: some View {
        let selected = selection == .feed
        return Button {
            Haptics.selection()
            selection = .feed
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#F1C8FA"))
                        .frame(width: 76, height: 76)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 5)
                        }
                        .shadow(color: accent.opacity(0.24), radius: 10, y: 4)
                    JojoMascot(height: 60, floats: false, pose: .book)
                        .clipShape(Circle())
                        .frame(width: 64, height: 64)
                    if vocabBadge > 0 {
                        Text("\(min(vocabBadge, 99))")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color(hex: "#FF9F1C"), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                            .offset(x: 29, y: -26)
                            .accessibilityLabel("\(vocabBadge) new vocabulary cards")
                    }
                }
                Text("Feed")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selected ? accent : muted)
                    .lineLimit(1)
                Capsule()
                    .fill(selected ? accent : Color.clear)
                    .frame(width: 34, height: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feed")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dockSymbol(_ symbol: String, selected: Bool) -> String {
        if !selected { return symbol }
        let filled = "\(symbol).fill"
        // Prefer the filled variant when it exists; otherwise keep the base name.
        return filled
    }

    private func sideItem(_ tab: AppTab, title: String, symbol: String) -> some View {
        let selected = selection == tab
        let tint = selected ? accent : muted
        return Button {
            Haptics.selection()
            selection = tab
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: dockSymbol(symbol, selected: selected))
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(tint)
                        .frame(width: 48, height: 32)
                }
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Capsule()
                    .fill(selected ? accent : Color.clear)
                    .frame(width: 18, height: 3)
            }
            .frame(width: 88)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Soft saddle with a raised center for the Feed panda.
private struct DockBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 22, y: h))
        path.addLine(to: CGPoint(x: w - 22, y: h))
        path.addQuadCurve(to: CGPoint(x: w, y: h - 22), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w, y: 22))
        path.addQuadCurve(to: CGPoint(x: w - 22, y: 8), control: CGPoint(x: w, y: 8))
        // Gentle rise under the panda.
        path.addCurve(
            to: CGPoint(x: w * 0.62, y: 4),
            control1: CGPoint(x: w * 0.82, y: 8),
            control2: CGPoint(x: w * 0.72, y: 4)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.38, y: 4),
            control1: CGPoint(x: w * 0.55, y: -2),
            control2: CGPoint(x: w * 0.45, y: -2)
        )
        path.addCurve(
            to: CGPoint(x: 22, y: 8),
            control1: CGPoint(x: w * 0.28, y: 4),
            control2: CGPoint(x: w * 0.18, y: 8)
        )
        path.addQuadCurve(to: CGPoint(x: 0, y: 22), control: CGPoint(x: 0, y: 8))
        path.addLine(to: CGPoint(x: 0, y: h - 22))
        path.addQuadCurve(to: CGPoint(x: 22, y: h), control: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// Quiet seigaiha texture in the dock corners — never interactive.
private struct DockWaveMotif: View {
    var body: some View {
        HStack {
            wave
            Spacer()
            wave
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .opacity(0.22)
    }

    private var wave: some View {
        Image(systemName: "water.waves")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.sakuraPink)
    }
}

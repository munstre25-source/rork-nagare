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

/// Compact dark dock: Vocab, Feed mascot, Profile.
struct JojoDock: View {
    @Binding var selection: AppTab
    var vocabBadge: Int = 0

    private let active = Color.white
    private let inactive = Color.white.opacity(0.52)

    var body: some View {
        HStack(spacing: 0) {
            dockItem(.vocab, title: "Vocab", symbol: "books.vertical") {
                badge
            }
            dockItem(.feed, title: "Feed", symbol: nil) {
                JojoMascot(height: 28, floats: false, pose: .book)
                    .frame(width: 32, height: 32)
            }
            dockItem(.profile, title: "Profile", symbol: "person") { EmptyView() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: 290)
        .background(Color(hex: "#10120F").opacity(0.96), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var badge: some View {
        if vocabBadge > 0 {
            Text("\(min(vocabBadge, 99))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, 3)
                .background(Color(hex: "#FF9418"), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(hex: "#10120F"), lineWidth: 2))
                .offset(x: 13, y: -11)
                .accessibilityLabel("\(vocabBadge) vocabulary reviews due")
        }
    }

    private func dockItem<Icon: View>(
        _ tab: AppTab,
        title: String,
        symbol: String?,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let selected = selection == tab
        let tint = selected ? active : inactive
        return Button {
            Haptics.selection()
            selection = tab
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 23, weight: .medium))
                            .foregroundStyle(tint)
                    }
                    icon()
                }
                .frame(height: 36)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(selected ? Color.white : .clear)
                    .frame(width: 16, height: 2)
                    .offset(y: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

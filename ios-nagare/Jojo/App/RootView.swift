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
    @State private var experiencePromptTask: Task<Void, Never>?
    private let guide = GuidanceCenter.shared

    private var anySheetUp: Bool {
        showFeedbackPrompt || showManualFeedback || showCancellationSurvey
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
            // The feed's focus timer hides navigation while a clip is playing and restores it
            // on interaction. Other tabs keep the dock pinned; maximize can hide it explicitly.
            if !app.hidesMainTabBar && (tab != .feed || !app.feedChromeHidden) {
                JojoDock(selection: $tab, vocabBadge: dueVocabNotificationCount)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(app.profile.scheme.colorScheme)
        .onAppear { JojoPalette.activate(theme: app.profile.theme, scheme: app.profile.scheme) }
        .onChange(of: tab) { _, newTab in
            if newTab != .feed {
                showingExplore = false
                app.feedChromeHidden = false
            }
            if newTab == .vocab { guide.noteOpenedVocab() }
            syncGuideVisibility()
            if newTab != .feed, app.pendingDeepLink == nil { scheduleExperiencePrompt() }
        }
        .onChange(of: showingExplore) { _, exploring in
            if exploring { app.feedChromeHidden = false }
            syncGuideVisibility()
        }
        .onChange(of: anySheetUp) { _, _ in syncGuideVisibility() }
        .onChange(of: app.calmMomentTick) { _, _ in
            if tab != .feed, app.pendingDeepLink == nil { scheduleExperiencePrompt() }
        }
        .onChange(of: guide.feedRequestTick) { _, _ in
            showingExplore = false
            tab = .feed
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
        .overlay { CoachOverlay() }
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
            // Counts opens only; the experience prompt shows at calm moments (see below).
            app.noteMainAppOpenAndShouldAskFeedback()
            syncGuideVisibility()
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

    private func syncGuideVisibility() {
        guide.feedVisible = tab == .feed && !showingExplore
        guide.blockedByPresentation = anySheetUp
    }

    /// The one-time "How's Jojo so far?" prompt: only off the feed (nothing playing), never
    /// during the tour, another sheet, or speaking practice. Waits a beat, then checks again.
    private func scheduleExperiencePrompt() {
        experiencePromptTask?.cancel()
        guard app.shouldPresentFeedbackPrompt,
              !app.isReviewSessionActive,
              !app.recentlyEndedReview else { return }
        let requestedTab = tab
        experiencePromptTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(FeedbackPromptConfig.calmDelaySeconds))
            guard !Task.isCancelled,
                  tab == requestedTab, tab != .feed,
                  app.shouldPresentFeedbackPrompt,
                  !app.isReviewSessionActive,
                  !app.recentlyEndedReview,
                  app.pendingDeepLink == nil,
                  guide.tourStep == nil,
                  guide.activeTip == nil,
                  !anySheetUp,
                  !app.hidesMainTabBar,
                  !SpeechPractice.isListening else { return }
            showFeedbackPrompt = true
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

/// Bottom navigation: Vocab, Feed (mascot), Profile. A compact floating pill, centered so it
/// covers almost nothing; the feed can tuck it away with a swipe and bring it back the same way.
struct JojoDock: View {
    @Binding var selection: AppTab
    var vocabBadge: Int = 0

    var body: some View {
        HStack(spacing: 2) {
            dockItem(.vocab, title: "Vocab", symbol: "books.vertical", hint: vocabHint) {
                badge
            }
            dockItem(.feed, title: "Feed", symbol: nil, hint: "Watch clips") {
                JojoMascot(height: 24, floats: false, pose: .book)
                    .frame(width: 28, height: 28)
                    .opacity(selection == .feed ? 1 : 0.6)
                    .saturation(selection == .feed ? 1 : 0.35)
            }
            dockItem(.profile, title: "Profile", symbol: "person", hint: "Progress and settings") { EmptyView() }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background {
            Capsule().fill(Color.canvas)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var vocabHint: String {
        vocabBadge > 0 ? "\(vocabBadge) words ready to review" : "Your saved words"
    }

    @ViewBuilder
    private var badge: some View {
        if vocabBadge > 0 {
            Text("\(min(vocabBadge, 99))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 3)
                .background(Color.designOrange, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.canvas, lineWidth: 2))
                .offset(x: 14, y: -9)
                .accessibilityHidden(true)
        }
    }

    private func dockItem<Icon: View>(
        _ tab: AppTab,
        title: String,
        symbol: String?,
        hint: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let selected = selection == tab
        let tint: Color = selected ? .designOrange : .secondary
        return Button {
            guard selection != tab else { return }
            Haptics.selection()
            selection = tab
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if let symbol {
                        Image(systemName: selected ? "\(symbol).fill" : symbol)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    icon()
                }
                .frame(height: 30)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .frame(minWidth: 84, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityValue(tab == .vocab && vocabBadge > 0 ? "\(vocabBadge) due" : "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .coachTarget(.vocabDock, active: tab == .vocab)
    }
}

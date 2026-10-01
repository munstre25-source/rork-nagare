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
                    JojoBrandBackground()
                    PaywallView(allowsDebugBypass: true) {}
                        .frame(maxWidth: 560)
                }
                .environment(\.brandSurface, .cream)
                .environment(\.colorScheme, .light)
                .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: app.profile.onboardingCompleted)
        .animation(.easeInOut(duration: 0.4), value: app.purchases.isSubscribed)
        .task(id: app.profile.onboardingCompleted) {
            // After onboarding, ask for ATT once so RevenueCat can attach IDFA when allowed.
            guard app.profile.onboardingCompleted else { return }
            try? await Task.sleep(for: .milliseconds(800))
            await MetaAttribution.requestTrackingIfNeededAndSync()
        }
    }
}

nonisolated enum AppTab: Hashable, Sendable {
    case feed, vocab, profile
}

/// Exactly three tabs: Feed, Vocab (badge = saved words), Profile.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Query private var words: [SavedWord]
    @State private var tab: AppTab = .feed
    @State private var showFeedbackPrompt = false
    @State private var showManualFeedback = false
    @State private var showCancellationSurvey = false

    var body: some View {
        TabView(selection: $tab) {
            FeedView(isActiveTab: tab == .feed)
                .tabItem {
                    Label("Feed", systemImage: tab == .feed ? "play.circle.fill" : "play.circle")
                }
                .tag(AppTab.feed)
                .toolbarBackground(Color.bgPlayer, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
            VocabView()
                .tabItem {
                    Label("Vocab", systemImage: tab == .vocab ? "book.fill" : "book")
                }
                .badge(words.count)
                .tag(AppTab.vocab)
            ProfileView(onGiveFeedback: { showManualFeedback = true })
                .tabItem {
                    Label("Profile", systemImage: tab == .profile ? "person.fill" : "person")
                }
                .tag(AppTab.profile)
        }
        .tint(Color.jojoVermilion)
        .preferredColorScheme(app.profile.appearance.colorScheme)
        .onChange(of: app.pendingFeedClipId) { _, id in
            if id != nil { tab = .feed }
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
        .onAppear {
            let badge = UITabBarItem.appearance()
            badge.badgeColor = UIColor(hex: "#FF6B00")
            if app.pendingDeepLink == .review { tab = .vocab }
            if app.pendingDeepLink == .feed { tab = .feed }
            if app.noteMainAppOpenAndShouldAskFeedback() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
            FeedbackFlowSheet { showManualFeedback = false }
        }
        .sheet(isPresented: $showCancellationSurvey) {
            CancellationSurveySheet { showCancellationSurvey = false }
        }
    }
}

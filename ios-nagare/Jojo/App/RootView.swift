import SwiftUI

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
                    JojoBrandBackground(scene: .lanternNight, showsHills: false)
                    PaywallView(allowsDebugBypass: true) {}
                        .frame(maxWidth: 560)
                }
                .environment(\.brandSurface, .night)
                .environment(\.colorScheme, .dark)
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
    case feed, vocab, explore, profile
}

/// Feed, Vocab, and Profile sit in the bottom bar. Explore opens from the top switch.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .feed
    @State private var showFeedbackPrompt = false
    @State private var showManualFeedback = false
    @State private var showCancellationSurvey = false
    /// New flashcards saved since the last visit to Vocab. The system badge shows only this count.
    @State private var newVocabSinceVisit: Int = 0
    @State private var showingExplore = false

    var body: some View {
        TabView(selection: $tab) {
            FeedTab(
                showingExplore: $showingExplore,
                feedActive: tab == .feed
            )
            .tabItem { Label("Feed", systemImage: "play.circle") }
            .tag(AppTab.feed)

            VocabView()
                .tabItem { Label("Vocab", systemImage: "book") }
                .tag(AppTab.vocab)
                .badge(newVocabSinceVisit)

            ProfileView(onGiveFeedback: { showManualFeedback = true })
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppTab.profile)
        }
        .tint(Color.designOrange)
        .preferredColorScheme(app.profile.appearance.colorScheme)
        .onChange(of: app.vocabBadgePulse) { _, _ in
            if tab != .vocab { newVocabSinceVisit += 1 }
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .vocab { newVocabSinceVisit = 0 }
            if newTab != .feed { showingExplore = false }
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
        .onAppear {
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
            FeedbackFlowSheet { showManualFeedback = false }
        }
        .sheet(isPresented: $showCancellationSurvey) {
            CancellationSurveySheet { showCancellationSurvey = false }
        }
    }
}

/// For You and Explore share the Feed tab, so the system tab bar stays on Feed, Vocab, and Profile.
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

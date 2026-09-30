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
                    OnboardingBackground()
                    PaywallView(allowsDebugBypass: true) {}
                        .frame(maxWidth: 560)
                }
                .environment(\.colorScheme, .dark)
                .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: app.profile.onboardingCompleted)
        .animation(.easeInOut(duration: 0.4), value: app.purchases.isSubscribed)
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
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: tab == .profile ? "person.fill" : "person")
                }
                .tag(AppTab.profile)
        }
        .tint(Color.adaptive(light: "#111111", dark: "#FFFFFF"))
        .onChange(of: app.pendingFeedClipId) { _, id in
            if id != nil { tab = .feed }
        }
        .onAppear {
            let badge = UITabBarItem.appearance()
            badge.badgeColor = UIColor(hex: "#FF6B00")
        }
    }
}

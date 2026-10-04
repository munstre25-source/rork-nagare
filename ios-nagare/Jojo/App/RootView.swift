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

/// Four tabs: Feed, Vocab, Explore, Profile.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Query private var words: [SavedWord]
    @State private var tab: AppTab = .feed
    @State private var showFeedbackPrompt = false
    @State private var showManualFeedback = false
    @State private var showCancellationSurvey = false
    /// New flashcards saved since last Vocab visit (0 = show total word count instead).
    @State private var newVocabSinceVisit: Int = 0
    @State private var tabBarHidden = false

    private var vocabBadge: Int {
        if tab == .vocab { return 0 }
        return newVocabSinceVisit > 0 ? newVocabSinceVisit : words.count
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                FeedView(isActiveTab: tab == .feed, onOpenExplore: { tab = .explore }, tabBarHidden: $tabBarHidden)
                    .tag(AppTab.feed)
                VocabView(tabBarHidden: $tabBarHidden)
                    .tag(AppTab.vocab)
                ExploreHomeView(onOpenFeed: { tab = .feed }, tabBarHidden: $tabBarHidden)
                    .tag(AppTab.explore)
                ProfileView(onGiveFeedback: { showManualFeedback = true }, tabBarHidden: $tabBarHidden)
                    .tag(AppTab.profile)
            }
            .toolbar(.hidden, for: .tabBar)

            if tabBarHidden {
                Color.clear
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            tabBarHidden = false
                        }
                    }
                    .accessibilityLabel("Show tabs")
            }

            FloatingTabBar(selection: $tab, vocabBadge: vocabBadge)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, 8)
                .offset(y: tabBarHidden ? 160 : 0)
                .opacity(tabBarHidden ? 0 : 1)
                .allowsHitTesting(!tabBarHidden)
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: tabBarHidden)
        }
        .tint(Color.designOrange)
        .preferredColorScheme(app.profile.appearance.colorScheme)
        .onChange(of: app.vocabBadgePulse) { _, _ in
            if tab != .vocab { newVocabSinceVisit += 1 }
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .vocab { newVocabSinceVisit = 0 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                tabBarHidden = false
            }
        }
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

/// Floating capsule tab bar matching Kiku's chrome.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var vocabBadge: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.feed, title: "Feed", systemImage: selection == .feed ? "house.fill" : "house")
            tabButton(.vocab, title: "Vocab", systemImage: selection == .vocab ? "book.fill" : "book", badge: vocabBadge)
            tabButton(.explore, title: "Explore", systemImage: selection == .explore ? "safari.fill" : "safari")
            tabButton(.profile, title: "Profile", systemImage: selection == .profile ? "person.fill" : "person")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: AppTab, title: String, systemImage: String, badge: Int = 0) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.tabSlide) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 28)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.sakuraFill, in: Capsule())
                            .offset(x: 10, y: -6)
                            .contentTransition(.numericText())
                    }
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selection == tab ? Color.designOrange : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(badge > 0 ? "\(badge) new" : "")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

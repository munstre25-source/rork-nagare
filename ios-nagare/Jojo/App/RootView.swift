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
                    JojoBrandBackground(scene: .templeDusk, showsHills: false)
                    PaywallView(allowsDebugBypass: false) {}
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

    /// True only on For You, once the learner has settled into a playing clip.
    private var focusCapsuleHidden: Bool {
        app.feedChromeHidden && tab == .feed && !showingExplore
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
                .badge(newVocabSinceVisit)

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
            if !app.hidesMainTabBar {
                KikuTabBar(selection: $tab, vocabBadge: newVocabSinceVisit)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .opacity(focusCapsuleHidden ? 0 : 1)
                    .offset(y: focusCapsuleHidden ? 14 : 0)
                    .allowsHitTesting(!focusCapsuleHidden)
                    .animation(.easeInOut(duration: 0.4), value: focusCapsuleHidden)
                    .accessibilityHidden(focusCapsuleHidden)
            }
        }
        .preferredColorScheme(app.profile.appearance.colorScheme)
        .onChange(of: app.vocabBadgePulse) { _, _ in
            if tab != .vocab { newVocabSinceVisit += 1 }
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .vocab { newVocabSinceVisit = 0 }
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

/// Kiku's bottom capsule: three icon-and-label buttons, centered, not a full-width bar.
struct KikuTabBar: View {
    @Binding var selection: AppTab
    var vocabBadge: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            item(.feed, title: "Feed", symbol: "play.circle")
            item(.vocab, title: "Vocab", symbol: "book", badge: vocabBadge)
            item(.profile, title: "Profile", symbol: "person")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func item(_ tab: AppTab, title: String, symbol: String, badge: Int = 0) -> some View {
        let selected = selection == tab
        return Button {
            Haptics.selection()
            selection = tab
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: selected ? "\(symbol).fill" : symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 24)
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.sakuraButton, in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.78))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

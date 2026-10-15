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

/// Library, Feed, Vocab, and Profile sit in the bottom bar. Explore opens from the top switch.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .feed
    @State private var showFeedbackPrompt = false
    @State private var showManualFeedback = false
    @State private var showCancellationSurvey = false
    /// New flashcards saved since the last visit to Vocab. The system badge shows only this count.
    @State private var newVocabSinceVisit: Int = 0
    @State private var showingExplore = false
    @State private var welcome: (due: Int, streak: Int)?
    @State private var flight: WordFlight?

    /// True only on For You, once the learner has settled into a playing clip.
    private var focusCapsuleHidden: Bool {
        app.feedChromeHidden && tab == .feed && !showingExplore
    }

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .toolbar(.hidden, for: .tabBar)
                .background(SystemTabBarHider())
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)

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
            // While a clip is playing the whole dock leaves the screen so the raised
            // panda never covers the video. It returns on tap, pause, or a dictionary card.
            if !app.hidesMainTabBar, !focusCapsuleHidden {
                JojoDock(selection: $tab, vocabBadge: newVocabSinceVisit)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: focusCapsuleHidden)
        .preferredColorScheme(app.profile.scheme.colorScheme)
        .onAppear { JojoPalette.activate(theme: app.profile.theme, scheme: app.profile.scheme) }
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
        .overlay {
            ZStack {
                if let welcome {
                    WelcomeHomeBurst(due: welcome.due, streak: welcome.streak)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if let flight {
                    WordFlightView(surface: flight.surface, reading: flight.reading)
                        .id(flight.id)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: app.rewardFlight) { _, next in
            guard let next else { return }
            flight = next
            Task {
                try? await Task.sleep(for: .milliseconds(1100))
                if flight?.id == next.id { flight = nil }
            }
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

/// Curved dock from the navigation board: Library, Vocab, raised Feed panda, Profile.
struct JojoDock: View {
    @Binding var selection: AppTab
    var vocabBadge: Int = 0
    @Environment(AppModel.self) private var app

    private var glow: GlowLevel { app.profile.glow }
    private var accent: Color { Color.sakuraPink }
    private var muted: Color { accent.opacity(0.55) }

    var body: some View {
        ZStack(alignment: .top) {
            DockBarShape()
                .fill(Color.dockFill.opacity(0.94))
                .overlay {
                    DockBarShape()
                        .stroke(accent.opacity(glow == .off ? 0.35 : 0.75), lineWidth: 1.2)
                }
                .chromeGlow(accent, level: glow, radius: 14)
                .overlay {
                    DockWaveMotif()
                        .allowsHitTesting(false)
                }
                .frame(height: 64)

            HStack(alignment: .bottom, spacing: 0) {
                sideItem(.library, title: "Library", symbol: "books.vertical")
                sideItem(.vocab, title: "Vocab", symbol: "book", badge: vocabBadge)
                Spacer(minLength: 0)
                feedItem
                Spacer(minLength: 0)
                sideItem(.profile, title: "Profile", symbol: "person")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .offset(y: -18)
        }
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
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
                        .fill(Color.dockFill)
                        .frame(width: 66, height: 66)
                        .overlay {
                            Circle()
                                .strokeBorder(accent, lineWidth: selected ? 2.5 : 1.5)
                        }
                        .chromeGlow(accent, level: glow, radius: selected ? 16 : 10)
                    JojoMascot(height: 52, floats: false, pose: .book)
                        .clipShape(Circle())
                        .frame(width: 56, height: 56)
                    // Petals around the panda — decorative only.
                    ForEach(0..<4, id: \.self) { i in
                        Blossom(size: i % 2 == 0 ? 10 : 7, color: accent.opacity(0.85))
                            .offset(
                                x: [22, -24, 20, -18][i],
                                y: [-18, -14, 16, 18][i]
                            )
                            .allowsHitTesting(false)
                    }
                }
                Text("Feed")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? accent : muted)
                    .lineLimit(1)
                Capsule()
                    .fill(selected ? accent : Color.clear)
                    .frame(width: 22, height: 3)
                    .chromeGlow(accent, level: selected ? glow : .off, radius: 4)
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

    private func sideItem(_ tab: AppTab, title: String, symbol: String, badge: Int = 0) -> some View {
        let selected = selection == tab
        let tint = selected ? accent : muted
        return Button {
            Haptics.selection()
            selection = tab
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: dockSymbol(symbol, selected: selected))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 26)
                        .textGlow(accent, level: selected ? glow : .off)
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.sakuraButton, in: Capsule())
                            .offset(x: 8, y: -6)
                            .modifier(BadgePop(value: badge))
                    }
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Capsule()
                    .fill(selected ? accent : Color.clear)
                    .frame(width: 18, height: 3)
            }
            .frame(width: 72)
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

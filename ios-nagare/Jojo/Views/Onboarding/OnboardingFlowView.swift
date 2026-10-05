import SwiftUI

/// Hosts every onboarding step. The current step is persisted so the app resumes on the exact screen.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var step: OnboardingStep = .splash
    @State private var showSplash: Bool = true
    @State private var isForward: Bool = true
    @State private var didLoad: Bool = false

    private var progressSteps: [OnboardingStep] { OnboardingStep.flow.filter(\.showsProgress) }

    var body: some View {
        ZStack {
            background
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSplash = false
                        if step == .splash {
                            go(to: .valueCaptions)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                VStack(spacing: 0) {
                    if step != .demo, step != .paywall {
                        header
                    }
                    content
                        .id(contentId)
                        .transition(.asymmetric(
                            insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
                        ))
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .environment(\.brandSurface, activeSurface)
        .environment(\.colorScheme, activeSurface == .cream ? .light : .dark)
        .animation(.easeInOut(duration: 0.35), value: activeSurface)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            step = OnboardingStep(rawValue: app.profile.onboardingStep) ?? .splash
            if step == .trialTimeline { step = .demo }
            if step == .welcome, !app.purchases.isSubscribed { step = .paywall }
            // Resume mid-funnel: skip splash.
            if step != .splash {
                showSplash = false
            }
        }
        .onChange(of: step) { _, newStep in
            app.setOnboardingStep(newStep)
            track("onboarding_\(newStep.analyticsName)_view", props: ["step": String(newStep.rawValue)])
        }
    }

    private var activeSurface: BrandSurface { step.surface }

    private var background: some View {
        JojoBrandBackground(
            scene: sceneForStep,
            showsHills: false,
            showsPetals: true
        )
        .animation(.easeInOut(duration: 0.45), value: sceneForStep)
    }

    private var sceneForStep: BrandScene {
        switch step {
        case .splash, .valueCaptions: .lanternNight
        case .valueTap: .neonTokyo
        case .valueFlashcards: .templeDusk
        case .paywall: .templeDusk
        case .welcome: .sakuraDay
        default: .lanternNight
        }
    }

    /// Value-prop pages share one carousel identity so they swipe instead of transitioning.
    private var contentId: String {
        switch step {
        case .valueCaptions, .valueTap, .valueFlashcards: "valueprop"
        default: "step-\(step.rawValue)"
        }
    }

    @ViewBuilder
    private var header: some View {
        let onNight = activeSurface != .cream
        HStack(spacing: Spacing.m) {
            if step.allowsBack, step != .valueTap, step != .valueFlashcards {
                Button {
                    back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(onNight ? .white : Color.jojoInk)
                        .frame(width: 44, height: 44)
                        .background(onNight ? Color.white.opacity(0.12) : Color.jojoPaper, in: Circle())
                        .overlay {
                            if !onNight {
                                Circle().strokeBorder(Color.jojoPaperStroke, lineWidth: 1)
                            }
                        }
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            if step.showsProgress, let index = progressSteps.firstIndex(of: step) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(onNight ? Color.white.opacity(0.14) : Color.jojoInk.opacity(0.08))
                        Capsule()
                            .fill(Color.sakuraPink)
                            .frame(width: proxy.size.width * CGFloat(index + 1) / CGFloat(progressSteps.count))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: index)
                    }
                }
                .frame(height: 6)
                .accessibilityElement()
                .accessibilityLabel("Step \(index + 1) of \(progressSteps.count)")
            } else {
                Spacer()
            }
            JojoMascotAvatar(size: 36)
                .opacity(step.showsProgress ? 1 : 0)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .opacity(step == .welcome ? 0 : 1)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .splash, .valueCaptions, .valueTap, .valueFlashcards:
            ValuePropCarousel(step: Binding(get: { step }, set: { newValue in
                isForward = newValue.flowIndex > step.flowIndex
                step = newValue
            })) { next() }
        case .name:
            NameStepView { next() }
        case .motivation:
            MotivationStepView { next() }
        case .taste:
            TasteSwipeStepView { next() }
        case .level:
            LevelStepView { next() }
        case .demo:
            OnboardingFeedDemoView(onContinue: { next() }, onBack: { back() })
        case .flashcardTry:
            FlashcardTryStepView { next() }
        case .socialProof:
            SocialProofStepView { next() }
        case .dailyGoal:
            DailyGoalStepView { next() }
        case .journey:
            JourneyStepView { next() }
        case .notifications:
            NotificationStepView { next() }
        case .trialTimeline:
            TrialTimelineStepView { next() }
        case .appReview:
            AppReviewStepView { next() }
        case .acquisition:
            AcquisitionStepView { next() }
        case .paywall:
            PaywallView(allowsDebugBypass: false) {
                go(to: .welcome)
            }
        case .welcome:
            WelcomeStepView {
                withAnimation(.easeInOut(duration: 0.5)) { app.completeOnboarding() }
            }
        }
    }

    private func next() {
        guard let nextStep = step.advanced(by: 1) else { return }
        go(to: nextStep)
    }

    private func back() {
        guard let previous = step.advanced(by: -1), previous != .splash else { return }
        Haptics.selection()
        isForward = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = previous }
    }

    private func go(to target: OnboardingStep) {
        isForward = target.flowIndex >= step.flowIndex
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = target }
    }
}

/// Splash: night lantern scene, peeking panda, wordmark brush stroke, then actions.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(AppModel.self) private var app
    @State private var progress: CGFloat = 0
    @State private var appeared: Bool = false
    @State private var peekIn: Bool = false
    @State private var showActions: Bool = false
    #if DEBUG
    @State private var marketingScript: MarketingScript?
    #endif

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: Spacing.l) {
                Spacer(minLength: 0)
                JojoLogo(drawProgress: progress, showsMascot: false, light: true)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)
                Spacer(minLength: 0)
                if showActions {
                    VStack(spacing: Spacing.m) {
                        Button {
                            Haptics.medium()
                            onFinish()
                        } label: {
                            Text("Get started")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        #if DEBUG
                        debugMarketingButtons
                        #endif
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            JojoMascot(height: 220, pose: .peek)
                .offset(x: peekIn ? 28 : 160, y: peekIn ? 20 : 60)
                .opacity(peekIn ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #if DEBUG
        .fullScreenCover(item: $marketingScript) { script in
            MarketingShowcaseView(initialScript: script, autoBegin: true)
        }
        #endif
        .task {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.15)) { peekIn = true }
            withAnimation(.easeInOut(duration: 0.8).delay(0.1)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showActions = true }
        }
    }

    #if DEBUG
    private var debugMarketingButtons: some View {
        VStack(spacing: Spacing.s) {
            Text("DEBUG")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.sakuraPink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Haptics.selection()
                marketingScript = .forYou
            } label: {
                Label("Play For You demo", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityHint("Silent walkthrough: feed, word tap, swipe, flashcard")
            Button {
                Haptics.selection()
                marketingScript = .exploreVocab
            } label: {
                Label("Play Explore & Vocab demo", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityHint("Silent walkthrough: explore, vocab, flashcards")
        }
        .padding(.top, Spacing.s)
    }
    #endif
}

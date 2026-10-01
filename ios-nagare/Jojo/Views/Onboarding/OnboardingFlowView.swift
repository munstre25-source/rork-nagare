import SwiftUI

/// Hosts every onboarding step. The current step is persisted so the app resumes on the exact screen.
struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var step: OnboardingStep = .splash
    @State private var showSplash: Bool = true
    @State private var showDemoGate: Bool = false
    @State private var showDemoPlayer: Bool = false
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
                        if shouldOfferLaunchDemo {
                            showDemoGate = true
                        } else if step == .splash {
                            go(to: .valueCaptions)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else if showDemoPlayer {
                AppMarketingDemoView {
                    finishLaunchDemo()
                }
                .transition(.opacity)
            } else if showDemoGate {
                LaunchDemoGateView(
                    onPlay: {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            showDemoGate = false
                            showDemoPlayer = true
                        }
                    },
                    onSkip: {
                        track("launch_demo_skip")
                        finishLaunchDemo()
                    }
                )
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    header
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
        .environment(\.colorScheme, activeSurface == .cinema ? .dark : .light)
        .animation(.easeInOut(duration: 0.35), value: activeSurface == .cinema)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            step = OnboardingStep(rawValue: app.profile.onboardingStep) ?? .splash
            if step == .welcome, !app.purchases.isSubscribed { step = .paywall }
            // Resume mid-funnel: skip splash + demo gate.
            if step != .splash {
                showSplash = false
                showDemoGate = false
            }
        }
        .onChange(of: step) { _, newStep in
            app.setOnboardingStep(newStep)
            track("onboarding_\(newStep.analyticsName)_view", props: ["step": String(newStep.rawValue)])
        }
    }

    /// The launch demo and the in-funnel video beat are the only dark moments.
    private var activeSurface: BrandSurface {
        if showDemoPlayer { return .cinema }
        return step.surface
    }

    @ViewBuilder
    private var background: some View {
        if activeSurface == .cinema {
            OnboardingBackground()
        } else {
            JojoBrandBackground(showsHills: !showSplash, showsPetals: true)
        }
    }

    private var shouldOfferLaunchDemo: Bool {
        !app.profile.hasSeenLaunchDemo && (step == .splash || step == .valueCaptions)
    }

    private func finishLaunchDemo() {
        app.markLaunchDemoSeen()
        withAnimation(.easeInOut(duration: 0.4)) {
            showDemoPlayer = false
            showDemoGate = false
            if step == .splash { go(to: .valueCaptions) }
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
        let onCream = activeSurface == .cream
        HStack(spacing: Spacing.m) {
            if step.allowsBack, step != .valueTap, step != .valueFlashcards {
                Button {
                    back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(onCream ? Color.jojoInk : .white)
                        .frame(width: 44, height: 44)
                        .background(onCream ? Color.jojoPaper : Color.white.opacity(0.08), in: Circle())
                        .overlay {
                            if onCream {
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
                        Capsule().fill(onCream ? Color.jojoInk.opacity(0.08) : Color.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [Color.jojoOrangeLight, Color.jojoVermilion], startPoint: .leading, endPoint: .trailing))
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
            DemoStepView { next() }
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
            PaywallView(allowsDebugBypass: true) {
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

/// 0. Splash: Jojo rises onto the cream paper, the brush stroke draws itself, then it dissolves.
struct SplashView: View {
    let onFinish: () -> Void
    @State private var progress: CGFloat = 0
    @State private var appeared: Bool = false

    var body: some View {
        JojoLogo(drawProgress: progress)
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
            .task {
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
                withAnimation(.easeInOut(duration: 0.8).delay(0.1)) { progress = 1 }
                try? await Task.sleep(for: .milliseconds(1250))
                onFinish()
            }
    }
}

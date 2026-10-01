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

    private var progressSteps: [OnboardingStep] { OnboardingStep.allCases.filter(\.showsProgress) }

    var body: some View {
        ZStack {
            if step.usesLightChrome {
                Color(hex: "#FFF6EE").ignoresSafeArea()
            } else {
                OnboardingBackground()
            }
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
        .environment(\.colorScheme, step.usesLightChrome ? .light : .dark)
        .animation(.easeInOut(duration: 0.35), value: step.usesLightChrome)
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
        let light = step.usesLightChrome
        HStack(spacing: Spacing.m) {
            if step.allowsBack, step != .valueTap, step != .valueFlashcards {
                Button {
                    back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(light ? Color(hex: "#3A3A3A") : .white)
                        .frame(width: 44, height: 44)
                        .background((light ? Color.black.opacity(0.06) : Color.white.opacity(0.08)), in: Circle())
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            if step.showsProgress, let index = progressSteps.firstIndex(of: step) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(light ? Color.black.opacity(0.08) : Color.white.opacity(0.12))
                        Capsule().fill(Color.nagareOrange)
                            .frame(width: proxy.size.width * CGFloat(index + 1) / CGFloat(progressSteps.count))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: index)
                    }
                }
                .frame(height: 5)
                .accessibilityElement()
                .accessibilityLabel("Step \(index + 1) of \(progressSteps.count)")
            } else {
                Spacer()
            }
            Color.clear.frame(width: 44, height: 44)
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
                isForward = newValue.rawValue > step.rawValue
                step = newValue
            })) { next() }
        case .motivation:
            MotivationStepView { next() }
        case .taste:
            TasteSwipeStepView { next() }
        case .level:
            LevelStepView { next() }
        case .demo:
            DemoStepView { next() }
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
        guard let nextStep = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        go(to: nextStep)
    }

    private func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1), previous != .splash else { return }
        Haptics.selection()
        isForward = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = previous }
    }

    private func go(to target: OnboardingStep) {
        isForward = target.rawValue >= step.rawValue
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = target }
    }
}

/// 0. Splash: logo in, orange stroke draws itself in under a second, then dissolves.
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

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
            if step == .demo { step = .flashcardTry }
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

    /// Cream brand canvas for every onboarding step.
    private var activeSurface: BrandSurface { step.surface }

    private var background: some View {
        JojoBrandBackground(showsHills: !showSplash, showsPetals: true)
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
        case .demo, .flashcardTry:
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

/// Splash: Jojo rises onto the cream paper, the brush stroke draws itself, then actions appear.
struct SplashView: View {
    let onFinish: () -> Void
    @State private var progress: CGFloat = 0
    @State private var appeared: Bool = false
    @State private var showActions: Bool = false
    @State private var showMarketingShowcase: Bool = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer(minLength: 0)
            JojoLogo(drawProgress: progress)
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

                    Button {
                        Haptics.selection()
                        showMarketingShowcase = true
                    } label: {
                        Label("Play marketing demo", systemImage: "record.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.jojoInk.opacity(0.72))
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Opens the silent marketing walkthrough without finishing onboarding")
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showMarketingShowcase) {
            MarketingShowcaseView()
        }
        .task {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.8).delay(0.1)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showActions = true }
        }
    }
}

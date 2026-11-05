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
                SplashView(onFinish: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSplash = false
                        if step == .splash {
                            go(to: .name)
                        }
                    }
                }, onRestored: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSplash = false
                        go(to: .welcome)
                    }
                })
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                VStack(spacing: 0) {
                    if step != .paywall {
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
            var restored = OnboardingStep(rawValue: app.profile.onboardingStep) ?? .splash
            // Older builds could resume inside a feature demo. Onboarding now gathers setup
            // preferences only, so those interrupted states restart at the setup flow.
            switch restored {
            case .valueCaptions, .valueTap, .valueFlashcards, .demo, .flashcardTry,
                 .socialProof, .journey, .trialTimeline, .appReview:
                restored = .name
            case .notifications:
                restored = .studyWindow
            case .buildingPlan:
                restored = .planReady
            default:
                break
            }
            if restored == .welcome, !app.purchases.isSubscribed { restored = .paywall }
            step = restored
            applyPalette(for: step)
            // Resume mid-funnel: skip splash.
            if step != .splash {
                showSplash = false
            }
            track("onboarding_\(step.analyticsName)_view", props: ["step": String(step.flowIndex)])
        }
        .onChange(of: step) { _, newStep in
            applyPalette(for: newStep)
            app.setOnboardingStep(newStep)
            // `step` is the position in the live flow so the dashboard funnel reads in screen order.
            track("onboarding_\(newStep.analyticsName)_view", props: ["step": String(newStep.flowIndex)])
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
        case .splash, .name: .lanternNight
        case .paywall: .templeDusk
        case .welcome: .sakuraDay
        default: .lanternNight
        }
    }

    private var contentId: String {
        "step-\(step.rawValue)"
    }

    @ViewBuilder
    private var header: some View {
        let onNight = activeSurface != .cream
        HStack(spacing: Spacing.m) {
            if step.allowsBack {
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
        case .splash:
            NameStepView { next() }
        case .name:
            NameStepView { next() }
        case .motivation:
            MotivationStepView { next() }
        case .taste:
            TasteSwipeStepView { next() }
        case .level:
            LevelStepView { next() }
        case .challenges:
            ChallengesStepView { next() }
        case .comparison:
            ComparisonStepView { next() }
        case .acquisition:
            AcquisitionStepView { next() }
        case .fluencyGoal:
            FluencyGoalStepView { next() }
        case .dailyGoal:
            DailyGoalStepView { next() }
        case .studyWindow:
            StudyWindowStepView { next() }
        case .streakCommit:
            StreakCommitStepView { next() }
        case .buildingPlan:
            BuildingPlanStepView { next() }
        case .planReady:
            PlanReadyStepView { next() }
        case .look:
            LookStepView { next() }
        case .trialReminder:
            TrialReminderStepView { next() }
        // These cases are only retained so interrupted onboarding from older builds decodes.
        // `onAppear` redirects them before the view becomes visible.
        case .valueCaptions, .valueTap, .valueFlashcards, .demo, .flashcardTry,
             .socialProof, .journey, .trialTimeline, .appReview, .notifications:
            Color.clear
        case .paywall:
            PaywallView(allowsDebugBypass: DebugFlags.allowPaywallBypass) {
                go(to: .welcome)
            }
        case .welcome:
            WelcomeStepView {
                withAnimation(.easeInOut(duration: 0.5)) { app.completeOnboarding() }
            }
        }
    }

    /// Sakura night for the funnel. The look they just saved paints the paywall and the welcome.
    private func applyPalette(for step: OnboardingStep) {
        switch step {
        case .look, .trialReminder, .paywall, .welcome:
            app.restorePalette()
        default:
            JojoPalette.activateOnboarding()
        }
    }

    private func next() {
        guard let nextStep = step.advanced(by: 1) else { return }
        go(to: nextStep)
    }

    private func back() {
        guard var previous = step.advanced(by: -1), previous != .splash else { return }
        // The plan builder is a one-way beat; stepping back skips over it.
        if previous == .buildingPlan, let earlier = previous.advanced(by: -1) { previous = earlier }
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
    var onRestored: () -> Void = {}
    @Environment(AppModel.self) private var app
    @State private var isRestoring = false
    @State private var restoreMessage: String?
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

                        Button {
                            Task { await restore() }
                        } label: {
                            HStack(spacing: Spacing.s) {
                                if isRestoring { ProgressView().tint(.white).controlSize(.small) }
                                Text("I already have Jojo Pro")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(isRestoring)
                        .accessibilityHint("Restores your subscription from the App Store")

                        #if DEBUG
                        debugSkipToFeedButton
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
        .alert("Restore purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .task {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.15)) { peekIn = true }
            withAnimation(.easeInOut(duration: 0.8).delay(0.1)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showActions = true }
        }
    }

    private func restore() async {
        Haptics.light()
        isRestoring = true
        let outcome = await app.purchases.restore()
        isRestoring = false
        switch outcome {
        case .success:
            track("onboarding_splash_restore_success")
            Haptics.success()
            onRestored()
        case .cancelled, .pending:
            break
        case .failed(let message):
            restoreMessage = message
        }
    }

    #if DEBUG
    private var debugSkipToFeedButton: some View {
        Button {
            Haptics.medium()
            // Keep the debug shortcut representative of a true first-run account: it opens
            // the real feed without demo vocabulary or watch history.
            app.purchases.activateDebugBypass()
            app.completeOnboarding(seedDemo: false)
        } label: {
            Label("DEBUG · Skip setup & paywall", systemImage: "forward.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.jojoOrange.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityHint("Opens the real feed with the debug paywall bypass")
    }

    private var debugMarketingButtons: some View {
        VStack(spacing: Spacing.s) {
            Text("DEBUG")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.sakuraPink)
                .frame(maxWidth: .infinity, alignment: .leading)
            debugDemoButton("1 · Sakura dark neon", script: .coreSakuraDarkNeon, hint: "Core For You story: 3 clips, tap, save, flashcards")
            debugDemoButton("2 · Sakura dark", script: .coreSakuraDarkOff, hint: "Same core story, glow off")
            debugDemoButton("3 · Amber dark neon", script: .coreAmberDarkNeon, hint: "Same core story on Amber neon")
            debugDemoButton("4 · Amber dark", script: .coreAmberDarkOff, hint: "Same core story on Amber, glow off")
            debugDemoButton("5 · Full app tour", script: .fullTour, hint: "Onboarding through Search, Library, Profile, every theme look")
        }
        .padding(.top, Spacing.s)
    }

    private func debugDemoButton(_ title: String, script: MarketingScript, hint: String) -> some View {
        Button {
            Haptics.selection()
            marketingScript = script
        } label: {
            Label(title, systemImage: "play.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityHint(hint)
    }
    #endif
}

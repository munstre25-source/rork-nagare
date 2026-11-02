import SwiftUI
import RevenueCat

nonisolated enum PlanChoice: Sendable {
    case yearly, monthly
}

/// Hard paywall in the onboarding style. No skip, no close button.
struct PaywallView: View {
    var allowsDebugBypass: Bool = false
    let onSubscribed: () -> Void

    @Environment(AppModel.self) private var app
    @State private var plan: PlanChoice = .yearly
    @State private var userSelectedPlan = false
    @State private var errorMessage: String?
    @State private var didTrackView: Bool = false
    @State private var appeared = false
    @State private var strokeProgress: CGFloat = 0
    @State private var peekIn = false
    @State private var kenBurns = false
    @State private var offeringTimedOut = false
    @State private var offeringWatch = 0
    @State private var restoreAlert: String?

    private var purchases: PurchaseManager { app.purchases }
    var body: some View {
        // The annual-first native comparison is the canonical onboarding offer.
        // RevenueCat still supplies products, localized prices, trials and entitlements.
        nativePaywall
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if allowsDebugBypass {
                Button("DEBUG · Skip paywall") {
                    purchases.activateDebugBypass()
                    onSubscribed()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.48), in: Capsule())
                .padding(.top, 8)
                .padding(.trailing, 8)
                .accessibilityHint("Available only in DEBUG builds")
            }
        }
        #endif
            .alert("Restore Purchases", isPresented: Binding(
                get: { restoreAlert != nil },
                set: { if !$0 { restoreAlert = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreAlert ?? "")
            }
            .onAppear {
                guard !didTrackView else { return }
                didTrackView = true
                track("onboarding_paywall_view", props: [
                    "offering_loaded": purchases.offering == nil ? "0" : "1",
                    "remote": "0",
                    "plan": "yearly"
                ])
                if purchases.offering == nil { Task { await purchases.loadOffering() } }
                watchOfferingLoad()
                if purchases.isSubscribed { onSubscribed() }
                withAnimation(.easeOut(duration: 0.35)) { appeared = true }
                withAnimation(.easeInOut(duration: 0.8).delay(0.1)) { strokeProgress = 1 }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.15)) { peekIn = true }
                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { kenBurns = true }
            }
            .onChange(of: purchases.isSubscribed) { _, subscribed in
                if subscribed { onSubscribed() }
            }
            .onChange(of: plansReady) { _, ready in
                if ready {
                    offeringTimedOut = false
                    if !userSelectedPlan, yearlyPrice != nil { plan = .yearly }
                }
            }
            .onChange(of: anyPlanReady) { _, _ in selectAvailablePlan() }
            .onChange(of: purchases.isLoadingOffering) { _, loading in
                if !loading { selectAvailablePlan() }
            }
            .onChange(of: offeringTimedOut) { _, _ in selectAvailablePlan() }
    }

    private var nativePaywall: some View {
        ZStack(alignment: .bottomTrailing) {
            paywallBackdrop
            BrandPetalField(tint: PaywallInk.pink, density: .lush)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    wordmark
                    headline
                    yearlyCard
                    monthlyCard
                    benefitRow
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.m)
                            .background(Color(hex: "#140C2E"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(spacing: 8) {
                        Text(trialCaption)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(subscriptionDisclosure)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color(hex: "#140C2E"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    trustRow
                    flourish
                    legalRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)

            JojoMascot(height: 150, floats: false, pose: .peek)
                .offset(x: peekIn ? 36 : 150, y: peekIn ? 24 : 70)
                .opacity(peekIn ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseDock }
    }

    private var purchaseDock: some View {
        VStack(spacing: 8) {
            if offeringUnavailable { offeringRetry } else { purchaseButton }
            Text(trialCaption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color(hex: "#140C2E").opacity(0.97))
    }

    private var paywallBackdrop: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#4A2A78"), Color(hex: "#6B2A58"), Color(hex: "#1A1028")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if UIImage(named: BrandScene.templeDusk.rawValue) != nil {
                    Image(BrandScene.templeDusk.rawValue)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(kenBurns ? 1.08 : 1.0)
                        .clipped()
                }
                Color.black.opacity(0.55)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            JojoMascotAvatar(size: 42, showsRing: true)
                .offset(x: peekIn ? 0 : -24)
                .opacity(peekIn ? 1 : 0)
            Text("JOJO")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(PaywallInk.pink)
            Text("PRO")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("🌸")
                .font(.system(size: 16))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Jojo Pro")
    }

    private var headline: some View {
        let name = app.profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = name.isEmpty ? "Your feed is ready" : "\(name), your feed is ready"
        return VStack(alignment: .leading, spacing: 10) {
            (
                Text("\(lead)\n")
                    .foregroundStyle(.white)
                + Text("Tap any word.")
                    .foregroundStyle(PaywallInk.pink)
            )
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .lineSpacing(1)
            AccentUnderline()
                .trim(from: 0, to: strokeProgress)
                .stroke(PaywallInk.pink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 168, height: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: -6)
            Text("Scroll real Japanese. The dictionary opens on the word you tap, and that word becomes a flashcard.")
                .font(.body)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefitRow: some View {
        HStack(alignment: .top, spacing: 8) {
            benefit("play.rectangle.fill", "Clips at your level", "The feed follows what you picked")
            benefit("text.magnifyingglass", "Tap any word", "Reading and meaning, in the sentence")
            benefit("rectangle.on.rectangle.angled", "Cards from the clip", "Review the line you just heard")
            benefit("iphone", "iPhone and iPad", "One Jojo Pro subscription")
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PaywallInk.pink)
                .frame(width: 46, height: 46)
                .background(PaywallInk.ink, in: Circle())
                .overlay(Circle().strokeBorder(PaywallInk.pink, lineWidth: 1.5))
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedPackage: Package? {
        plan == .yearly ? purchases.yearly : purchases.monthly
    }

    private var trialLine: String {
        let text = purchases.trialText(selectedPackage)
        return text.isEmpty ? "" : text.prefix(1).uppercased() + text.dropFirst()
    }

    private var selectedPackageHasTrial: Bool { !purchases.trialText(selectedPackage).isEmpty }

    /// "Start Free Trial" only when the selected product really offers one to this user.
    private var primaryCTATitle: String {
        guard selectedPlanReady else { return "Loading Plans…" }
        return plan == .yearly && selectedPackageHasTrial ? "Start Free Trial" : "Continue"
    }

    /// Apple 3.1.2-style disclosure: title length, price, trial, auto-renew, and how to cancel.
    private var subscriptionDisclosure: String {
        let renew = "Payment is charged to your Apple ID. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions."
        guard let price = purchases.priceText(selectedPackage),
              let period = purchases.periodSuffix(selectedPackage) else {
            return "Plans load from the App Store. \(renew)"
        }
        if selectedPackageHasTrial, !trialLine.isEmpty {
            return "\(trialLine), then \(price)/\(period) for Jojo Pro. \(renew)"
        }
        return "\(price)/\(period) for Jojo Pro. \(renew)"
    }

    private var yearlyPrice: String? { purchases.priceText(purchases.yearly) }
    private var monthlyPrice: String? { purchases.priceText(purchases.monthly) }
    /// Every plan has loaded.
    private var plansReady: Bool { yearlyPrice != nil && monthlyPrice != nil }
    /// At least one plan can be bought; each plan is purchasable on its own.
    private var anyPlanReady: Bool { yearlyPrice != nil || monthlyPrice != nil }
    private var selectedPlanLoaded: Bool { purchases.priceText(selectedPackage) != nil }
    private var selectedPlanReady: Bool { selectedPlanLoaded && !purchases.isLoadingOffering }
    /// Offerings failed, or nothing has arrived within 8 seconds.
    private var offeringUnavailable: Bool {
        !anyPlanReady && (purchases.offeringFailed || offeringTimedOut)
    }
    /// One plan loaded but this one did not.
    private var planMissing: Bool {
        anyPlanReady && (purchases.offeringFailed || offeringTimedOut)
    }

    private var perMonthLine: String? {
        guard let amount = purchases.perMonthText(purchases.yearly) else { return nil }
        return "Equivalent to \(amount)/month"
    }

    private var saveBadge: String? {
        guard let percent = purchases.yearlySavingsPercent() else { return nil }
        return "Save \(percent)%"
    }

    private var yearlyCard: some View {
        planButton(.yearly) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Image(systemName: plan == .yearly ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(plan == .yearly ? PaywallInk.pink : PaywallInk.ink)
                    Text("Annual")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(PaywallInk.ink)
                    Spacer(minLength: 8)
                    if let saveBadge {
                        Text(saveBadge)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(PaywallInk.pink, in: Capsule())
                    }
                }
                if let yearlyPrice, let period = purchases.periodSuffix(purchases.yearly) {
                    Text("\(yearlyPrice) / \(period)")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(PaywallInk.ink)
                } else if offeringUnavailable || planMissing {
                    Text(planMissing ? "Not available right now" : "Plans didn’t load")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PaywallInk.ink)
                } else {
                    ProgressView().tint(PaywallInk.pink)
                }
                if let perMonthLine {
                    HStack(spacing: 8) {
                        if purchases.annualComparison?.hasSavings == true, let monthlyPrice {
                            Text("\(monthlyPrice)/mo")
                                .strikethrough()
                                .font(.subheadline)
                                .foregroundStyle(PaywallInk.ink.opacity(0.6))
                        }
                        Text(perMonthLine)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PaywallInk.ink)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let savings = purchases.yearlySavingsText() {
                    Text("Save \(savings) over 12 monthly payments")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PaywallInk.ink)
                }
                Text("One payment for a full year of Jojo Pro")
                    .font(.caption)
                    .foregroundStyle(PaywallInk.ink.opacity(0.8))
                HStack(spacing: 0) {
                    planMeta("play.rectangle.fill", "Whole feed")
                    planMeta("text.magnifyingglass", "Every word")
                    planMeta("clock", "Cancel anytime")
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(PaywallInk.pink, lineWidth: plan == .yearly ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                Label(purchases.annualComparison?.hasSavings == true ? "Best Value" : "Recommended", systemImage: "crown.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PaywallInk.pink, in: Capsule())
                    .offset(y: -12)
                    .padding(.trailing, 14)
            }
        }
        .padding(.top, 10)
    }

    private var monthlyCard: some View {
        planButton(.monthly) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: plan == .monthly ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(plan == .monthly ? PaywallInk.pink : .white)
                    Text("Monthly")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
                if let monthlyPrice, let period = purchases.periodSuffix(purchases.monthly) {
                    Text("\(monthlyPrice) / \(period)")
                        .font(.system(plan == .monthly ? .title : .title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                } else if offeringUnavailable || planMissing {
                    Text(planMissing ? "Not available right now" : "Plans didn’t load")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
                Text("Same access, billed monthly")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                if let total = purchases.monthlyYearTotalText() {
                    Text("\(total) over 12 monthly payments")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                HStack(spacing: 16) {
                    Label("Whole feed", systemImage: "checkmark")
                    Label("Cancel anytime", systemImage: "checkmark")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(PaywallInk.monthly, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(plan == .monthly ? PaywallInk.pink : .white, lineWidth: plan == .monthly ? 2.5 : 1)
            )
        }
    }

    private func planButton<Label: View>(_ choice: PlanChoice, @ViewBuilder label: () -> Label) -> some View {
        Button {
            Haptics.selection()
            userSelectedPlan = true
            withAnimation(.snappy) { plan = choice }
            track("onboarding_plan_selected", props: ["plan": choice == .yearly ? "yearly" : "monthly"])
        } label: {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PressableStyle())
        .disabled(purchases.isPurchasing || purchases.isRestoring)
        .accessibilityAddTraits(plan == choice ? .isSelected : [])
    }

    private func planMeta(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(PaywallInk.pink)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PaywallInk.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var purchaseButton: some View {
        Button {
            Task { await buy() }
        } label: {
            if purchases.isPurchasing || purchases.isRestoring {
                ProgressView().tint(.white)
            } else {
                HStack(spacing: 8) {
                    Text(primaryCTATitle)
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.bold))
                }
                .contentTransition(.opacity)
            }
        }
        .buttonStyle(PaywallCTAStyle())
        .disabled(!selectedPlanReady || purchases.isPurchasing || purchases.isRestoring)
    }

    private var offeringRetry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn’t load plans. Check your connection and try again.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Button {
                Task { await retryOffering() }
            } label: {
                if purchases.isLoadingOffering {
                    ProgressView().tint(.white)
                } else {
                    Text("Try again")
                }
            }
            .buttonStyle(PaywallCTAStyle())
            .disabled(purchases.isLoadingOffering)
        }
    }

    private var trialCaption: String {
        if offeringUnavailable {
            return "Plans didn’t load. Restore still works if you already subscribed."
        }
        guard let price = purchases.priceText(selectedPackage),
              let period = purchases.periodSuffix(selectedPackage) else {
            return "Loading plans from the App Store"
        }
        if selectedPackageHasTrial, !trialLine.isEmpty {
            return "\(trialLine)  ·  Then \(price)/\(period)"
        }
        return "\(price)/\(period)  ·  Cancel anytime"
    }

    private var trustRow: some View {
        HStack(alignment: .top, spacing: 8) {
            trust("apple.logo", "Billed by Apple", "Charged to your Apple ID")
            trust("iphone", "iPhone and iPad", "The Jojo app")
            trust("arrow.clockwise", "Cancel anytime", "In Apple subscriptions")
        }
        .padding(.top, 6)
    }

    private func trust(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color(hex: "#140C2E"), in: Circle())
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var flourish: some View {
        Text("♥  一緒にがんばろう  ♥")
            .font(.system(size: 22, weight: .medium, design: .serif))
            .italic()
            .foregroundStyle(PaywallInk.pink)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityLabel("Let's do this together")
    }

    private var legalRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                if let terms = StoreConstants.termsURL { Link("Terms of Service", destination: terms) }
                if let privacy = StoreConstants.privacyURL { Link("Privacy Policy", destination: privacy) }
            }
            .frame(minHeight: 44)
            HStack(spacing: 18) {
                if let support = StoreConstants.supportURL { Link("Support", destination: support) }
                Button("Restore Purchases") { Task { await restore() } }
                    .disabled(purchases.isRestoring || purchases.isPurchasing)
            }
            .frame(minHeight: 44)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private func buy() async {
        Haptics.medium()
        withAnimation { errorMessage = nil }
        let purchasingPlan = plan
        let package = selectedPackage
        track("onboarding_payment_start", props: ["plan": purchasingPlan == .yearly ? "yearly" : "monthly"])
        let outcome = await purchases.purchase(package)
        switch outcome {
        case .success:
            Haptics.success()
            track("onboarding_payment_success", props: ["plan": purchasingPlan == .yearly ? "yearly" : "monthly"])
            scheduleTrialReminderNow(trialDays: purchases.trialLengthDays(package))
            onSubscribed()
        case .cancelled:
            track("onboarding_payment_cancelled")
        case .pending:
            track("onboarding_payment_pending")
            withAnimation { errorMessage = "Waiting for approval. Jojo unlocks automatically once it's approved." }
        case .failed(let message):
            track("onboarding_payment_failed")
            withAnimation { errorMessage = message }
        }
    }

    /// Uses the trial end date when RevenueCat has it. Otherwise counts forward from today.
    /// Later reminder opt-in is handled by `AppModel.refreshTrialReminder()`.
    private func scheduleTrialReminderNow(trialDays: Int?) {
        guard app.profile.remindersEnabled else { return }
        if let status = purchases.status, status.isInTrial, let expiration = status.expirationDate {
            NotificationService.scheduleTrialReminder(endingAt: expiration)
        } else if let trialDays {
            NotificationService.scheduleTrialReminder(trialDays: trialDays)
        }
    }

    private func watchOfferingLoad() {
        offeringWatch += 1
        let watch = offeringWatch
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard watch == offeringWatch, !plansReady else { return }
            offeringTimedOut = true
        }
    }

    /// If the chosen plan never loads but the other did, switch to the one that can be bought.
    private func selectAvailablePlan() {
        guard anyPlanReady, !selectedPlanLoaded else { return }
        if purchases.offeringFailed || offeringTimedOut || plansReady || !purchases.isLoadingOffering {
            plan = (plan == .yearly) ? .monthly : .yearly
        }
    }

    private func retryOffering() async {
        offeringTimedOut = false
        errorMessage = nil
        await purchases.loadOffering()
        if !plansReady { offeringTimedOut = true }
        watchOfferingLoad()
    }

    private func restore() async {
        let outcome = await purchases.restore()
        switch outcome {
        case .success:
            track("onboarding_restore_success")
            onSubscribed()
        case .cancelled, .pending:
            break
        case .failed(let message):
            restoreAlert = message
        }
    }
}

private enum PaywallInk {
    static let pink = Color(hex: "#FC45A5")
    static let pinkHot = Color(hex: "#FD4FA7")
    static let pinkDeep = Color(hex: "#E21888")
    static let card = Color(hex: "#FDECF8")
    static let monthly = Color(hex: "#3C2644")
    static let ink = Color(hex: "#3A1848")
}

private struct PaywallCTAStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.sakuraButton, in: Capsule())
            .shadow(color: Color.sakuraButton.opacity(0.4), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

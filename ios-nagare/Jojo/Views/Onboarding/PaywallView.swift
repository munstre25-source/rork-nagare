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
    @State private var errorMessage: String?
    @State private var didTrackView: Bool = false

    private var purchases: PurchaseManager { app.purchases }

    var body: some View {
        nativePaywall
            .onAppear {
                guard !didTrackView else { return }
                didTrackView = true
                track("onboarding_paywall_view", props: [
                    "offering_loaded": purchases.offering == nil ? "0" : "1",
                    "remote": "0"
                ])
                if purchases.offering == nil { Task { await purchases.loadOffering() } }
                if purchases.isSubscribed { onSubscribed() }
            }
            .onChange(of: purchases.isSubscribed) { _, subscribed in
                if subscribed { onSubscribed() }
            }
    }

    private var nativePaywall: some View {
        ZStack {
            paywallBackdrop
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    wordmark
                    headline
                    benefitRow
                    yearlyCard
                    monthlyCard
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.m)
                            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    purchaseButton
                    Text(trialCaption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    trustRow
                    flourish
                    legalRow
                    Text(subscriptionDisclosure)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paywallBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#3A1458"), Color(hex: "#6B2A78"), Color(hex: "#140818")],
                startPoint: .top,
                endPoint: .bottom
            )
            if UIImage(named: BrandScene.templeDusk.rawValue) != nil {
                Image(BrandScene.templeDusk.rawValue)
                    .resizable()
                    .scaledToFill()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.18), Color.black.opacity(0.08), Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            JojoMascotAvatar(size: 42, showsRing: true)
            Text("JOJO")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.sakuraPink)
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
                    .foregroundStyle(Color.sakuraPink)
            )
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .lineSpacing(1)
            Text("Scroll real Japanese. The dictionary opens on the word you tap, and that word becomes a flashcard.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
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
                .foregroundStyle(Color.sakuraPink)
                .frame(width: 46, height: 46)
                .background(Color.sakuraPinkSoft, in: Circle())
                .overlay(Circle().strokeBorder(Color.sakuraPink, lineWidth: 1.5))
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
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

    /// The button promises a trial only when the selected StoreKit product includes one.
    private var primaryCTATitle: String {
        selectedPackageHasTrial ? "Start Free Trial" : "Subscribe"
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
    private var plansReady: Bool { yearlyPrice != nil && monthlyPrice != nil }

    private var perMonthLine: String? {
        guard let amount = purchases.perMonthText(purchases.yearly) else { return nil }
        return "Only \(amount)/month"
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
                        .foregroundStyle(plan == .yearly ? Color.white : Color.sakuraPinkSoft)
                    Text("Yearly")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer(minLength: 8)
                    if let saveBadge {
                        Text(saveBadge)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.sakuraPink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white, in: Capsule())
                    }
                }
                if let yearlyPrice, let period = purchases.periodSuffix(purchases.yearly) {
                    Text("\(yearlyPrice) / \(period)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                } else {
                    ProgressView().tint(.white)
                }
                if let perMonthLine {
                    Text(perMonthLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 0) {
                    planMeta("play.rectangle.fill", "Whole feed")
                    planMeta("text.magnifyingglass", "Every word")
                    planMeta("clock", "Cancel anytime")
                }
                .padding(.top, 4)
            }
            .padding(16)
            .padding(.top, 8)
            .background(Color.sakuraButton, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Label("Most Popular", systemImage: "crown.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.sakuraPink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white, in: Capsule())
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
                        .foregroundStyle(plan == .monthly ? Color.sakuraPink : Color.sakuraPinkSoft)
                    Text("Monthly")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
                if let monthlyPrice, let period = purchases.periodSuffix(purchases.monthly) {
                    Text("\(monthlyPrice) / \(period)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                } else {
                    ProgressView().tint(.white)
                }
                Text("Same feed, billed each month")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 16) {
                    Label("Whole feed", systemImage: "checkmark")
                    Label("Cancel anytime", systemImage: "checkmark")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 2)
            }
            .padding(16)
            .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(plan == .monthly ? Color.sakuraPink : Color.white.opacity(0.16), lineWidth: plan == .monthly ? 2 : 1)
            )
        }
    }

    private func planButton<Label: View>(_ choice: PlanChoice, @ViewBuilder label: () -> Label) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { plan = choice }
        } label: {
            label()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(plan == choice ? .isSelected : [])
    }

    private func planMeta(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.sakuraPink)
            Text(title)
                .font(.caption2.weight(.semibold))
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
        .disabled(!plansReady || purchases.isPurchasing || purchases.isRestoring)
    }

    private var trialCaption: String {
        guard let price = purchases.priceText(selectedPackage),
              let period = purchases.periodSuffix(selectedPackage) else {
            return "Loading plans from the App Store"
        }
        if selectedPackageHasTrial, let days = purchases.trialLengthDays(selectedPackage) {
            return "\(days) days free  ·  Then \(price)/\(period)"
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
                .background(Color.white.opacity(0.1), in: Circle())
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var flourish: some View {
        Text("♥  一緒にがんばろう  ♥")
            .font(.system(size: 22, weight: .medium, design: .serif))
            .italic()
            .foregroundStyle(Color.sakuraPink)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityLabel("Let's do this together")
    }

    private var legalRow: some View {
        HStack(spacing: 8) {
            if let terms = StoreConstants.termsURL {
                Link("Terms of Service", destination: terms)
            }
            Text("|").foregroundStyle(Color.sakuraPinkSoft)
            if let privacy = StoreConstants.privacyURL {
                Link("Privacy Policy", destination: privacy)
            }
            Text("|").foregroundStyle(Color.sakuraPinkSoft)
            if let support = StoreConstants.supportURL {
                Link("Support", destination: support)
            }
            Text("|").foregroundStyle(Color.sakuraPinkSoft)
            Button("Restore Purchases") { Task { await restore() } }
                .disabled(purchases.isRestoring || purchases.isPurchasing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
    }

    private func buy() async {
        Haptics.medium()
        withAnimation { errorMessage = nil }
        track("onboarding_payment_start", props: ["plan": plan == .yearly ? "yearly" : "monthly"])
        let outcome = await purchases.purchase(selectedPackage)
        switch outcome {
        case .success:
            Haptics.success()
            track("onboarding_payment_success", props: ["plan": plan == .yearly ? "yearly" : "monthly"])
            if await NotificationService.isAuthorized(),
               let days = purchases.trialLengthDays(selectedPackage) {
                NotificationService.scheduleTrialReminder(trialDays: days)
            }
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

    private func restore() async {
        let outcome = await purchases.restore()
        switch outcome {
        case .success:
            track("onboarding_restore_success")
            onSubscribed()
        case .cancelled, .pending:
            break
        case .failed(let message):
            withAnimation { errorMessage = message }
        }
    }
}

private struct PaywallCTAStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.sakuraFill, in: Capsule())
            .shadow(color: Color.black.opacity(0.28), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

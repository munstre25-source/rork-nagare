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
    @Environment(\.openURL) private var openURL
    @State private var plan: PlanChoice = .yearly
    @State private var errorMessage: String?
    @State private var didTrackView: Bool = false

    private var purchases: PurchaseManager { app.purchases }

    var body: some View {
        Group {
            if let offering = purchases.offering, offering.hasPaywall {
                RemotePaywallView(offering: offering, onSubscribed: onSubscribed) { message in
                    withAnimation { errorMessage = message }
                }
                .overlay(alignment: .top) { remoteBanner }
            } else {
                nativePaywall
            }
        }
        .onAppear {
            guard !didTrackView else { return }
            didTrackView = true
            track("onboarding_paywall_view", props: [
                "offering_loaded": purchases.offering == nil ? "0" : "1",
                "remote": purchases.hasRemotePaywall ? "1" : "0"
            ])
            if purchases.offering == nil { Task { await purchases.loadOffering() } }
            if purchases.isSubscribed { onSubscribed() }
        }
        .onChange(of: purchases.isSubscribed) { _, subscribed in
            if subscribed { onSubscribed() }
        }
    }

    @ViewBuilder
    private var remoteBanner: some View {
        VStack(spacing: Spacing.s) {
            if let errorMessage {
                Button {
                    withAnimation { self.errorMessage = nil }
                } label: {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(Spacing.m)
                        .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            #if DEBUG
            if allowsDebugBypass, DebugFlags.allowPaywallBypass {
                Button("DEBUG: Skip paywall") {
                    purchases.activateDebugBypass()
                    onSubscribed()
                }
                .font(.caption.monospaced())
                .foregroundStyle(.yellow)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: 44)
                .background(.black.opacity(0.6), in: Capsule())
            }
            #endif
        }
        .padding(.top, Spacing.s)
    }

    private var nativePaywall: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("流れ PRO")
                            .font(JojoFont.jp(14, bold: true, relativeTo: .caption))
                            .tracking(2)
                            .foregroundStyle(Color.nagareOrange)
                        OnboardingTitle(title: "Flow into Japanese, every day.",
                                        subtitle: "Unlimited clips, tap-to-understand on every word and flashcards that build themselves.")
                    }
                    planCard(.yearly,
                             title: "Yearly",
                             price: purchases.priceText(purchases.yearly, fallback: StoreConstants.fallbackYearlyPrice) + " / year",
                             detail: purchases.yearlyPerMonthText(),
                             badge: "Save 50%",
                             package: purchases.yearly)
                    planCard(.monthly,
                             title: "Monthly",
                             price: purchases.priceText(purchases.monthly, fallback: StoreConstants.fallbackMonthlyPrice) + " / month",
                             detail: "Billed monthly",
                             badge: nil,
                             package: purchases.monthly)
                    if let errorMessage {
                        HStack(alignment: .top, spacing: Spacing.s) {
                            Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(Color.nagareOrange)
                            Text(errorMessage).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.nagareOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            footer
        }
    }

    private var selectedPackage: Package? {
        plan == .yearly ? purchases.yearly : purchases.monthly
    }

    private var trialLine: String {
        let text = purchases.trialText(selectedPackage)
        return text.isEmpty ? "" : text.prefix(1).uppercased() + text.dropFirst()
    }

    private var selectedPackageHasTrial: Bool { !purchases.trialText(selectedPackage).isEmpty }

    /// Apple 3.1.2-style disclosure: title length, price, trial, auto-renew, and how to cancel.
    private var subscriptionDisclosure: String {
        let price = purchases.priceText(
            selectedPackage,
            fallback: plan == .yearly ? StoreConstants.fallbackYearlyPrice : StoreConstants.fallbackMonthlyPrice
        )
        let period = plan == .yearly ? "year" : "month"
        if selectedPackageHasTrial, !trialLine.isEmpty {
            return "\(trialLine), then \(price)/\(period) for Jojo Pro. Payment is charged to your Apple ID. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions."
        }
        return "\(price)/\(period) for Jojo Pro. No free trial on Monthly. Payment is charged to your Apple ID. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions."
    }

    private func planCard(_ choice: PlanChoice, title: String, price: String, detail: String, badge: String?, package: Package?) -> some View {
        let isSelected = plan == choice
        return Button {
            Haptics.selection()
            withAnimation(.snappy) { plan = choice }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.nagareOrange : .white.opacity(0.35))
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
                    Spacer()
                    if let badge {
                        Text(badge).font(.caption.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.nagareOrange, in: Capsule())
                    }
                }
                Text(price).font(.headline).foregroundStyle(.white)
                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                if isSelected, !purchases.trialText(package).isEmpty {
                    Label(purchases.trialText(package).capitalizedFirst + ", then " + price, systemImage: "gift.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nagareOrange)
                        .transition(.opacity)
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                .strokeBorder(isSelected ? Color.nagareOrange : Color.hairlineDark, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: Spacing.s) {
            Button {
                Task { await buy() }
            } label: {
                if purchases.isPurchasing || purchases.isRestoring {
                    ProgressView().tint(.white)
                } else {
                    Text(selectedPackageHasTrial ? "Start My Free Trial" : "Subscribe Now")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(purchases.isPurchasing || purchases.isRestoring)
            Text(subscriptionDisclosure)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.l) {
                Button("Restore Purchases") { Task { await restore() } }
                    .disabled(purchases.isRestoring || purchases.isPurchasing)
                if let terms = StoreConstants.termsURL { Button("Terms") { openURL(terms) } }
                if let privacy = StoreConstants.privacyURL { Button("Privacy") { openURL(privacy) } }
                if let support = StoreConstants.supportURL { Button("Support") { openURL(support) } }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.65))
            .frame(minHeight: 44)
            #if DEBUG
            if allowsDebugBypass, DebugFlags.allowPaywallBypass {
                Button("DEBUG: Skip paywall (simulator only)") {
                    purchases.activateDebugBypass()
                    onSubscribed()
                }
                .font(.caption.monospaced())
                .foregroundStyle(.yellow.opacity(0.8))
                .frame(minHeight: 44)
            }
            #endif
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)
        .padding(.top, Spacing.s)
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

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

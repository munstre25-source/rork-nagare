import Foundation
import Observation
import RevenueCat

/// RevenueCat product/entitlement constants. Must match the RevenueCat dashboard and App Store Connect.
nonisolated enum StoreConstants {
    static let entitlementId = "nagare_learn_japanese_pro"
    static let offeringId = "default"
    static let monthlyProductId = "monthly"
    static let yearlyProductId = "yearly"
    static let termsURL = URL(string: "https://socialreporthq.com/jojo/terms")
    static let privacyURL = URL(string: "https://socialreporthq.com/jojo/privacy")
    static let supportURL = URL(string: "https://socialreporthq.com/jojo/support")
    static let supportEmail = "support@socialreporthq.com"
}

/// DEBUG-only paywall bypass so the app can be previewed in the simulator without StoreKit.
/// Compiled out of release builds entirely.
nonisolated enum DebugFlags {
    #if DEBUG
    static let allowPaywallBypass = true
    #else
    static let allowPaywallBypass = false
    #endif
}

nonisolated enum PurchaseOutcome: Sendable {
    case success
    case cancelled
    /// Awaiting Ask to Buy / SCA approval. Access unlocks automatically via `customerInfoStream`.
    case pending
    case failed(String)
}

/// Snapshot of the active entitlement for display (Profile, Customer Center entry).
nonisolated struct SubscriptionStatus: Sendable, Equatable {
    let productId: String
    let expirationDate: Date?
    let willRenew: Bool
    let isInTrial: Bool
    let isSandbox: Bool
}

/// Single source of truth for subscription state.
///
/// Identity: RevenueCat's **anonymous** app user ID only. `logIn` is never called, so every purchase,
/// restore and entitlement check is tied to `Purchases.shared.appUserID` (a `$RCAnonymousID:…` that
/// RevenueCat persists on device). Restore re-syncs the Apple ID's receipt onto that same anonymous ID.
@Observable
@MainActor
final class PurchaseManager {
    private(set) var isEntitlementActive = false
    private(set) var customerInfo: CustomerInfo?
    private(set) var status: SubscriptionStatus?
    private(set) var offering: Offering?
    private(set) var isLoadingOffering = false
    private(set) var eligibleTrialProductIds: Set<String> = []
    var isTrialEligible: Bool { !eligibleTrialProductIds.isEmpty }
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var offeringFailed = false
    private(set) var debugBypassActive = false
    /// Set when we observe trial auto-renew turn off so the UI can ask why.
    private(set) var pendingCancellationSurvey = false
    private var streamTask: Task<Void, Never>?
    private var previousWillRenew: Bool?
    private var previousInTrial: Bool?
    private static let bypassKey = "nagare.debug.bypass"
    private static let localIdKey = "nagare.local.anon.id"
    /// Last known entitlement, used until RevenueCat delivers fresh CustomerInfo (avoids a paywall flash at launch).
    private static let cachedEntitlementKey = "nagare.entitlement.cached"

    var isConfigured: Bool { Purchases.isConfigured }
    var isSubscribed: Bool { isEntitlementActive || debugBypassActive }
    var monthly: Package? {
        guard let package = offering?.monthly ?? offering?.package(identifier: StoreConstants.monthlyProductId),
              let period = package.storeProduct.subscriptionPeriod, period.unit == .month, period.value == 1 else { return nil }
        return package
    }
    var yearly: Package? {
        guard let package = offering?.annual ?? offering?.package(identifier: StoreConstants.yearlyProductId),
              let period = package.storeProduct.subscriptionPeriod, period.unit == .year, period.value == 1 else { return nil }
        return package
    }
    /// True when a RevenueCat Paywall is configured for the offering in the dashboard.
    var hasRemotePaywall: Bool { offering?.hasPaywall == true }

    /// RevenueCat anonymous app user ID, or a stable local ID when RevenueCat isn't configured.
    var appUserId: String { Self.currentAppUserId }

    /// Same id, for callers without a PurchaseManager instance.
    static var currentAppUserId: String {
        if Purchases.isConfigured { return Purchases.shared.appUserID }
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.localIdKey) { return existing }
        let created = "$local:\(UUID().uuidString)"
        defaults.set(created, forKey: Self.localIdKey)
        return created
    }

    var isAnonymous: Bool { Purchases.isConfigured ? Purchases.shared.isAnonymous : true }

    init() {
        isEntitlementActive = UserDefaults.standard.bool(forKey: Self.cachedEntitlementKey)
        #if DEBUG
        debugBypassActive = UserDefaults.standard.bool(forKey: Self.bypassKey)
        #endif
    }

    /// Call exactly once from `App.init()`.
    func configure() {
        guard Secrets.isRevenueCatConfigured else {
            print("[Purchases] RevenueCat API key not set, running without RevenueCat")
            offeringFailed = true
            isEntitlementActive = false
            #if DEBUG
            // Unblock onboarding/feed when secrets aren't wired yet.
            activateDebugBypass()
            #endif
            return
        }
        guard !Purchases.isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        // No appUserID passed → RevenueCat generates and persists an anonymous ID.
        Purchases.configure(with: Configuration.Builder(withAPIKey: Secrets.revenueCatAPIKey).build())
        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
        Task { await loadOffering() }
    }

    // MARK: Offerings

    func loadOffering() async {
        guard Purchases.isConfigured else {
            offeringFailed = true
            return
        }
        offeringFailed = false
        isLoadingOffering = true
        defer { isLoadingOffering = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            // Respect RevenueCat targeting/experiments; keep the configured default as fallback.
            offering = offerings.current ?? offerings.offering(identifier: StoreConstants.offeringId)
            offeringFailed = offering == nil
            if offering == nil {
                print("[Purchases] no '\(StoreConstants.offeringId)' offering; check the RevenueCat dashboard")
            }
            await refreshTrialEligibility()
        } catch {
            print("[Purchases] offerings error: \(error.localizedDescription)")
            offeringFailed = true
        }
    }

    private func refreshTrialEligibility() async {
        let packages = [monthly, yearly].compactMap { $0 }
        guard !packages.isEmpty else { return }
        eligibleTrialProductIds = []
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: packages)
        eligibleTrialProductIds = Set(eligibility.compactMap { package, result in
            result.status == .eligible ? package.storeProduct.productIdentifier : nil
        })
    }

    // MARK: Purchase

    func purchase(_ package: Package?) async -> PurchaseOutcome {
        guard Purchases.isConfigured else {
            return .failed("The App Store isn't reachable right now. Please try again in a moment.")
        }
        guard let package else {
            await loadOffering()
            return .failed("Plans are still loading. Give it another try.")
        }
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            apply(result.customerInfo)
            if isEntitlementActive {
                track("purchase_success", props: ["product": package.storeProduct.productIdentifier])
                return .success
            }
            return .failed("Your purchase went through but access isn't active yet. Tap Restore Purchases.")
        } catch {
            return outcome(for: error, context: "purchase")
        }
    }

    // MARK: Restore

    /// Restores the Apple ID's App Store purchases onto the **current anonymous app user ID**.
    /// We never call `logIn`, so the ID before and after restore is the same anonymous ID; RevenueCat
    /// transfers or aliases the receipt to it according to the project's restore behavior setting.
    func restore() async -> PurchaseOutcome {
        guard Purchases.isConfigured else {
            return .failed("The App Store isn't reachable right now. Please try again in a moment.")
        }
        guard !isRestoring else { return .cancelled }
        isRestoring = true
        defer { isRestoring = false }
        let userBefore = Purchases.shared.appUserID
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            print("[Purchases] restore for anonymous user \(Self.redact(userBefore)) → active: \(isEntitlementActive)")
            track("restore_complete", props: ["active": isEntitlementActive ? "1" : "0"])
            return isEntitlementActive ? .success : .failed("No active subscription was found for this Apple ID.")
        } catch {
            return outcome(for: error, context: "restore")
        }
    }

    // MARK: Customer info

    func refreshCustomerInfo() async {
        guard Purchases.isConfigured else { return }
        do {
            apply(try await Purchases.shared.customerInfo())
        } catch {
            print("[Purchases] customerInfo error: \(error.localizedDescription)")
        }
    }

    /// Called by RevenueCatUI (paywall / Customer Center) callbacks.
    func handleExternal(_ info: CustomerInfo) {
        apply(info)
    }

    func clearCancellationSurvey() {
        pendingCancellationSurvey = false
    }

    #if DEBUG
    /// DEBUG ONLY: unlocks the app without StoreKit. The Edge Function will reject calls (no real entitlement),
    /// so explanations silently come from the local dictionary.
    func activateDebugBypass() {
        debugBypassActive = true
        UserDefaults.standard.set(true, forKey: Self.bypassKey)
    }

    /// DEBUG: force the cancellation survey UI without a real StoreKit cancel.
    func debugTriggerCancellationSurvey() {
        pendingCancellationSurvey = true
    }
    #endif

    private func apply(_ info: CustomerInfo) {
        customerInfo = info
        let entitlement = info.entitlements.all[StoreConstants.entitlementId]
        let active = entitlement?.isActive == true
        let willRenew = entitlement?.willRenew == true
        let inTrial = entitlement?.periodType == .trial

        // Trial started → user turned off renewal (still entitled until trial ends),
        // or access dropped right after a trial cancel.
        let canceledTrialRenewal =
            previousWillRenew == true
            && !willRenew
            && (inTrial || previousInTrial == true)
        let lostTrialAccess =
            previousInTrial == true
            && previousWillRenew == true
            && !active
        if canceledTrialRenewal || lostTrialAccess {
            pendingCancellationSurvey = true
            track("trial_cancellation_detected", props: [
                "still_active": active ? "1" : "0",
                "in_trial": inTrial ? "1" : "0",
            ])
        }

        previousWillRenew = active ? willRenew : false
        previousInTrial = active ? inTrial : false

        isEntitlementActive = active
        if let entitlement, entitlement.isActive {
            status = SubscriptionStatus(
                productId: entitlement.productIdentifier,
                expirationDate: entitlement.expirationDate,
                willRenew: entitlement.willRenew,
                isInTrial: entitlement.periodType == .trial,
                isSandbox: entitlement.isSandbox
            )
        } else {
            status = nil
        }
        UserDefaults.standard.set(isEntitlementActive, forKey: Self.cachedEntitlementKey)
    }

    private func outcome(for error: Error, context: String) -> PurchaseOutcome {
        let code = (error as? ErrorCode) ?? ErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .purchaseCancelledError:
            return .cancelled
        case .paymentPendingError:
            return .pending
        case .networkError, .offlineConnectionError:
            return .failed("You look offline. Check your connection and try again.")
        case .productAlreadyPurchasedError, .receiptAlreadyInUseError:
            return .failed("This Apple ID already has Jojo Pro. Tap Restore Purchases.")
        case .purchaseNotAllowedError:
            return .failed("Purchases are turned off on this device (Screen Time or restrictions).")
        case .storeProblemError:
            return .failed("The App Store had a hiccup. No charge was made, so feel free to try again.")
        default:
            print("[Purchases] \(context) error: \(error.localizedDescription)")
            return .failed(context == "restore"
                ? "Couldn't reach the App Store. Please try again."
                : "That didn't go through. No charge was made, so feel free to try again.")
        }
    }

    private static func redact(_ id: String) -> String {
        id.count > 8 ? "…" + id.suffix(6) : id
    }

    // MARK: Display helpers

    func priceText(_ package: Package?) -> String? {
        package?.storeProduct.localizedPriceString
    }

    /// Billing period taken from the StoreKit product, e.g. "year" or "month".
    func periodSuffix(_ package: Package?) -> String? {
        guard let period = package?.storeProduct.subscriptionPeriod else { return nil }
        let value = period.value
        switch period.unit {
        case .day: return value == 1 ? "day" : "\(value) days"
        case .week: return value == 1 ? "week" : "\(value) weeks"
        case .month: return value == 1 ? "month" : "\(value) months"
        case .year: return value == 1 ? "year" : "\(value) years"
        @unknown default: return nil
        }
    }

    /// Free-trial copy from the product's introductory offer. Empty when StoreKit has no free trial.
    func trialText(_ package: Package?) -> String {
        guard let package, hasEligibleTrial(package) else { return "" }
        guard let discount = package.storeProduct.introductoryDiscount, discount.paymentMode == .freeTrial else { return "" }
        let period = discount.subscriptionPeriod
        let value = period.value
        switch period.unit {
        case .day: return "\(value)-day free trial"
        case .week: return "\(value * 7)-day free trial"
        case .month: return value == 1 ? "1-month free trial" : "\(value)-month free trial"
        case .year: return value == 1 ? "1-year free trial" : "\(value)-year free trial"
        @unknown default: return "Free trial"
        }
    }

    /// Trial length in days, from the introductory offer. Nil when that offer is not a free trial.
    func trialLengthDays(_ package: Package?) -> Int? {
        guard let package, hasEligibleTrial(package) else { return nil }
        guard let discount = package.storeProduct.introductoryDiscount, discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    /// Price of a plan spread across a month, using the product's own price and subscription period.
    func perMonthText(_ package: Package?) -> String? {
        guard let product = package?.storeProduct,
              let months = Self.monthCount(product.subscriptionPeriod),
              months > 0 else { return nil }
        let perMonth = product.price / months
        return currencyText(perMonth, product: product)
    }

    /// Only a verified trial for this selected product may be advertised.
    func hasEligibleTrial(_ package: Package?) -> Bool {
        guard let package else { return false }
        return eligibleTrialProductIds.contains(package.storeProduct.productIdentifier)
    }

    var annualComparison: SubscriptionPriceComparison? {
        guard let annual = yearly?.storeProduct, let month = monthly?.storeProduct,
              let annualPeriod = annual.subscriptionPeriod, annualPeriod.unit == .year,
              let monthlyPeriod = month.subscriptionPeriod, monthlyPeriod.unit == .month else { return nil }
        return SubscriptionPriceComparison(
            annualPrice: annual.price, monthlyPrice: month.price,
            annualCurrency: annual.currencyCode, monthlyCurrency: month.currencyCode,
            annualMonths: annualPeriod.value * 12, monthlyMonths: monthlyPeriod.value
        )
    }

    func yearlySavingsPercent() -> Int? {
        guard let comparison = annualComparison, comparison.savingsPercent > 0 else { return nil }
        return comparison.savingsPercent
    }

    func yearlySavingsText() -> String? {
        guard let comparison = annualComparison, comparison.hasSavings else { return nil }
        return currencyText(comparison.annualSavings, product: yearly?.storeProduct)
    }

    func monthlyYearTotalText() -> String? {
        guard let comparison = annualComparison else { return nil }
        return currencyText(comparison.twelveMonthsAtMonthlyPrice, product: monthly?.storeProduct)
    }

    private func currencyText(_ amount: Decimal, product: StoreProduct?) -> String? {
        guard let product, let currency = product.currencyCode, !currency.isEmpty else { return nil }
        if let formatter = product.priceFormatter?.copy() as? NumberFormatter {
            formatter.currencyCode = currency
            return formatter.string(from: amount as NSDecimalNumber)
        }
        return amount.formatted(.currency(code: currency))
    }

    private static func monthCount(_ period: SubscriptionPeriod?) -> Decimal? {
        guard let period else { return nil }
        switch period.unit {
        case .day: return Decimal(period.value) / 30
        case .week: return Decimal(period.value) * 12 / 52
        case .month: return Decimal(period.value)
        case .year: return Decimal(period.value) * 12
        @unknown default: return nil
        }
    }
}

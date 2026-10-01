import Foundation
import Observation
import RevenueCat

/// RevenueCat product/entitlement constants. Must match the RevenueCat dashboard and App Store Connect.
nonisolated enum StoreConstants {
    static let entitlementId = "nagare_learn_japanese_pro"
    static let offeringId = "default"
    static let monthlyProductId = "monthly"
    static let yearlyProductId = "yearly"
    static let fallbackMonthlyPrice = "$9.99"
    static let fallbackYearlyPrice = "$59.99"
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    static let privacyURL = URL(string: "https://nagare.app/privacy")
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
    private(set) var isTrialEligible = true
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var offeringFailed = false
    private(set) var debugBypassActive = false
    private var streamTask: Task<Void, Never>?
    private static let bypassKey = "nagare.debug.bypass"
    private static let localIdKey = "nagare.local.anon.id"
    /// Last known entitlement, used until RevenueCat delivers fresh CustomerInfo (avoids a paywall flash at launch).
    private static let cachedEntitlementKey = "nagare.entitlement.cached"

    var isConfigured: Bool { Purchases.isConfigured }
    var isSubscribed: Bool { isEntitlementActive || debugBypassActive }
    var monthly: Package? { offering?.monthly ?? offering?.package(identifier: StoreConstants.monthlyProductId) }
    var yearly: Package? { offering?.annual ?? offering?.package(identifier: StoreConstants.yearlyProductId) }
    /// True when a RevenueCat Paywall is configured for the offering in the dashboard.
    var hasRemotePaywall: Bool { offering?.hasPaywall == true }

    /// RevenueCat anonymous app user ID, or a stable local ID when RevenueCat isn't configured.
    var appUserId: String {
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
        isLoadingOffering = true
        defer { isLoadingOffering = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.offering(identifier: StoreConstants.offeringId) ?? offerings.current
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
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: packages)
        isTrialEligible = eligibility.values.contains { $0.status == .eligible || $0.status == .unknown }
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

    #if DEBUG
    /// DEBUG ONLY: unlocks the app without StoreKit. The Edge Function will reject calls (no real entitlement),
    /// so explanations silently come from the local dictionary.
    func activateDebugBypass() {
        debugBypassActive = true
        UserDefaults.standard.set(true, forKey: Self.bypassKey)
    }
    #endif

    private func apply(_ info: CustomerInfo) {
        customerInfo = info
        let entitlement = info.entitlements.all[StoreConstants.entitlementId]
        isEntitlementActive = entitlement?.isActive == true
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

    func priceText(_ package: Package?, fallback: String) -> String {
        package?.storeProduct.localizedPriceString ?? fallback
    }

    /// e.g. "7-day free trial", read from the product's introductory discount.
    func trialText(_ package: Package?) -> String {
        guard isTrialEligible else { return "" }
        guard let discount = package?.storeProduct.introductoryDiscount else { return "7-day free trial" }
        guard discount.paymentMode == .freeTrial else { return "Intro offer available" }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day: return "\(period.value)-day free trial"
        case .week: return period.value == 1 ? "7-day free trial" : "\(period.value)-week free trial"
        case .month: return "\(period.value)-month free trial"
        case .year: return "\(period.value)-year free trial"
        @unknown default: return "Free trial"
        }
    }

    /// Monthly-equivalent price for the yearly plan, e.g. "$5.00/mo".
    func yearlyPerMonthText() -> String {
        guard let product = yearly?.storeProduct else { return "$5.00/mo" }
        let perMonth = product.price / 12
        let formatter = product.priceFormatter ?? {
            let f = NumberFormatter()
            f.numberStyle = .currency
            return f
        }()
        return (formatter.string(from: perMonth as NSDecimalNumber) ?? "") + "/mo"
    }
}

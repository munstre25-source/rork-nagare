import Foundation
import UIKit
import FacebookCore
import RevenueCat
import AppTrackingTransparency

/// Boots the Meta (Facebook) SDK for install/attribution matching and pushes
/// `$fbAnonId` / device IDs into RevenueCat so the Meta Ads Conversions API can match purchases.
///
/// Purchase / subscription revenue events must **not** be logged by the Meta SDK —
/// RevenueCat already sends those via Conversions API.
enum MetaAttribution {
    private static var didPrepare = false

    /// Call from `UIApplicationDelegate.didFinishLaunching`. Safe if Meta secrets are missing.
    @discardableResult
    static func prepareSDK(
        application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard Secrets.isMetaConfigured else { return false }
        guard !didPrepare else {
            return ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        didPrepare = true

        Settings.shared.appID = Secrets.metaAppID
        Settings.shared.clientToken = Secrets.metaClientToken
        Settings.shared.displayName = "Jojo"
        // RevenueCat owns Subscribe / StartTrial / renewals — avoid double-counting.
        Settings.shared.isAutoLogAppEventsEnabled = false
        // IDFA collection stays off until ATT returns .authorized.
        Settings.shared.isAdvertiserIDCollectionEnabled = false
        Settings.shared.isAdvertiserTrackingEnabled = false

        return ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    static func handleOpenURL(_ url: URL) -> Bool {
        guard Secrets.isMetaConfigured else { return false }
        return ApplicationDelegate.shared.application(
            UIApplication.shared,
            open: url,
            sourceApplication: nil,
            annotation: [:]
        )
    }

    static func activateApp() {
        guard Secrets.isMetaConfigured else { return }
        AppEvents.shared.activateApp()
    }

    /// Push matching identifiers into RevenueCat. Call after `Purchases.configure` and again after ATT.
    static func syncToRevenueCat() {
        guard Secrets.isMetaConfigured, Purchases.isConfigured else { return }
        Purchases.shared.attribution.collectDeviceIdentifiers()
        let anon = AppEvents.shared.anonymousID
        if !anon.isEmpty {
            Purchases.shared.attribution.setFBAnonymousID(anon)
        }
    }

    /// Ask for ATT once (if needed), then refresh IDFA / `$fbAnonId` on the RevenueCat customer.
    @MainActor
    static func requestTrackingIfNeededAndSync() async {
        guard Secrets.isMetaConfigured else { return }
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        let authorized = ATTrackingManager.trackingAuthorizationStatus == .authorized
        Settings.shared.isAdvertiserTrackingEnabled = authorized
        Settings.shared.isAdvertiserIDCollectionEnabled = authorized
        syncToRevenueCat()
    }
}

/// Hooks Meta into the UIKit lifecycle for SwiftUI `@main`.
final class JojoAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = MetaAttribution.prepareSDK(application: application, launchOptions: launchOptions)
        return true
    }
}

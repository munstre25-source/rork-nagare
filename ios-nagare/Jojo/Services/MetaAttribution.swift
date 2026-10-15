import Foundation
import UIKit
import UserNotifications
import FacebookCore
import RevenueCat

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

    /// Push matching identifiers into RevenueCat. Does not request tracking permission.
    static func syncToRevenueCat() {
        guard Secrets.isMetaConfigured, Purchases.isConfigured else { return }
        Purchases.shared.attribution.collectDeviceIdentifiers()
        let anon = AppEvents.shared.anonymousID
        if !anon.isEmpty {
            Purchases.shared.attribution.setFBAnonymousID(anon)
        }
    }
}

extension Notification.Name {
    static let jojoOpenDeepLink = Notification.Name("jojo.openDeepLink")
}

/// Hooks Meta into the UIKit lifecycle for SwiftUI `@main`, and routes local-notification deep links.
final class JojoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var pendingNotificationURL: URL?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = MetaAttribution.prepareSDK(application: application, launchOptions: launchOptions)
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo["deepLink"] as? String,
           let url = URL(string: link) {
            JojoAppDelegate.pendingNotificationURL = url
            NotificationCenter.default.post(name: .jojoOpenDeepLink, object: url)
        }
        completionHandler()
    }
}

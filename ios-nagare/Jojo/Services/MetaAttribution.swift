import Foundation
import UIKit
import UserNotifications
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
        // Don't send an install or session event until the person has answered the tracking prompt.
        guard ATTrackingManager.trackingAuthorizationStatus != .notDetermined else { return }
        AppEvents.shared.activateApp()
    }

    /// Push matching identifiers into RevenueCat. Call after `Purchases.configure` and again after ATT.
    static func syncToRevenueCat() {
        guard Secrets.isMetaConfigured, Purchases.isConfigured else { return }
        guard ATTrackingManager.trackingAuthorizationStatus != .notDetermined else { return }
        Purchases.shared.attribution.collectDeviceIdentifiers()
        let anon = AppEvents.shared.anonymousID
        if !anon.isEmpty {
            Purchases.shared.attribution.setFBAnonymousID(anon)
        }
    }

    /// Ask for tracking as soon as the window is on screen, before any ad event is sent.
    /// Not gated on Meta keys or onboarding: the prompt has to appear on a fresh install, including iPad.
    @MainActor
    static func requestTrackingIfNeededAndSync() async {
        if requestInFlight { return }
        requestInFlight = true
        defer { requestInFlight = false }

        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            for _ in 0..<30 {
                if UIApplication.shared.applicationState == .active { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // One beat after the first frame so iPad has a key window to present the dialog.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                _ = await ATTrackingManager.requestTrackingAuthorization()
            }
        }
        let authorized = ATTrackingManager.trackingAuthorizationStatus == .authorized
        Settings.shared.isAdvertiserTrackingEnabled = authorized
        Settings.shared.isAdvertiserIDCollectionEnabled = authorized
        guard Secrets.isMetaConfigured else { return }
        syncToRevenueCat()
        activateApp()
    }

    private static var requestInFlight = false
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

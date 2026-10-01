import SwiftUI
import RevenueCat
import RevenueCatUI

/// Hosts the RevenueCat dashboard-designed paywall (RevenueCatUI) for the `default` offering.
/// Shown instead of the built-in paywall whenever a paywall is published for that offering,
/// so pricing/copy can be iterated remotely without an app update. No close button (hard paywall).
struct RemotePaywallView: View {
    let offering: Offering
    let onSubscribed: () -> Void
    let onRestoreFailed: (String) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        RevenueCatUI.PaywallView(offering: offering, displayCloseButton: false)
            .onPurchaseCompleted { info in
                app.purchases.handleExternal(info)
                track("remote_paywall_purchase", props: ["active": app.purchases.isSubscribed ? "1" : "0"])
                if app.purchases.isSubscribed {
                    Haptics.success()
                    onSubscribed()
                }
            }
            .onRestoreCompleted { info in
                app.purchases.handleExternal(info)
                if app.purchases.isSubscribed {
                    onSubscribed()
                } else {
                    onRestoreFailed("No active subscription was found for this Apple ID.")
                }
            }
            .onPurchaseFailure { error in
                print("[Purchases] paywall purchase failed: \(error.localizedDescription)")
            }
    }
}

/// RevenueCat Customer Center: manage plan, cancel, refund requests, restore, feedback survey.
struct JojoCustomerCenter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        CustomerCenterView()
            .onCustomerCenterRestoreCompleted { info in
                app.purchases.handleExternal(info)
            }
            .onCustomerCenterRestoreFailed { error in
                print("[Purchases] customer center restore failed: \(error.localizedDescription)")
            }
    }
}

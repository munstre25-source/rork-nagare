//
//  JojoApp.swift
//  Jojo
//
//  流れ: Scroll, Listen, Flow into Japanese.
//

import SwiftUI
import SwiftData

@main
struct JojoApp: App {
    @UIApplicationDelegateAdaptor(JojoAppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var purchases: PurchaseManager
    @State private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerFonts()
        UITabBar.appearance().isHidden = true
        let schema = Schema([SavedWord.self, CachedExplanation.self, UserProfile.self, RemoteClip.self, CustomDeck.self])
        // CloudKit-compatible models, but sync is intentionally disabled in this version.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        let resolved: ModelContainer
        do {
            resolved = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("[Jojo] persistent store failed (\(error.localizedDescription)); using in-memory store")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                resolved = try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Unable to create any ModelContainer: \(error)")
            }
        }
        container = resolved
        let manager = PurchaseManager()
        manager.configure()
        _purchases = State(initialValue: manager)
        _app = State(initialValue: AppModel(container: resolved, purchases: manager))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(purchases)
                .modelContainer(container)
                .task {
                    app.startRemoteSync()
                    await purchases.refreshCustomerInfo()
                    WidgetSnapshotPublisher.publish(from: app)
                    MetaAttribution.activateApp()
                    MetaAttribution.syncToRevenueCat()
                }
                .onOpenURL { url in
                    if MetaAttribution.handleOpenURL(url) { return }
                    app.handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await purchases.refreshCustomerInfo() }
                WidgetSnapshotPublisher.publish(from: app)
                MetaAttribution.activateApp()
                MetaAttribution.syncToRevenueCat()
                app.refreshAllReminders()
            }
        }
    }
}

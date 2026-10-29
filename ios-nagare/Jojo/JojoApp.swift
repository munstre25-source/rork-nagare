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
    @State private var launch: AppLaunch
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerFonts()
        UITabBar.appearance().isHidden = true
        LibraryStore.logReleaseConfiguration()
        _launch = State(initialValue: AppLaunch.open())
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let session):
                RootView()
                    .background(ActivityTouchObserver().allowsHitTesting(false))
                    .environment(session.app)
                    .environment(session.purchases)
                    .modelContainer(session.container)
                    .task {
                        session.app.startRemoteSync()
                        await session.purchases.refreshCustomerInfo()
                        session.app.refreshAllReminders()
                        WidgetSnapshotPublisher.publish(from: session.app)
                        ImmersionIsland.endStale()
                        await MetaAttribution.requestTrackingIfNeededAndSync()
                    }
                    .onOpenURL { url in
                        if MetaAttribution.handleOpenURL(url) { return }
                        session.app.handleDeepLink(url)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .jojoOpenDeepLink)) { note in
                        if let url = note.object as? URL {
                            session.app.handleDeepLink(url)
                        }
                    }
                    .onAppear {
                        if let url = JojoAppDelegate.pendingNotificationURL {
                            JojoAppDelegate.pendingNotificationURL = nil
                            session.app.handleDeepLink(url)
                        }
                    }
            case .unavailable:
                LibraryRecoveryView(
                    onRetry: { launch = AppLaunch.open() },
                    onReset: {
                        LibraryStore.reset()
                        launch = AppLaunch.open()
                    }
                )
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            SessionTracker.shared.setPhase(phase)
            guard phase == .active, case .ready(let session) = launch else { return }
            Task {
                await session.purchases.refreshCustomerInfo()
                session.app.refreshAllReminders()
            }
            WidgetSnapshotPublisher.publish(from: session.app)
            Task { await MetaAttribution.requestTrackingIfNeededAndSync() }
        }
    }
}

/// A launched library, or a blocked open so we never keep writing into a throwaway memory store.
@MainActor
enum AppLaunch {
    case ready(AppSession)
    case unavailable

    static func open() -> AppLaunch {
        do {
            let container = try LibraryStore.makeContainer()
            let manager = PurchaseManager()
            manager.configure()
            let app = AppModel(container: container, purchases: manager)
            return .ready(AppSession(container: container, purchases: manager, app: app))
        } catch {
            print("[Jojo] persistent store failed (\(error.localizedDescription))")
            return .unavailable
        }
    }
}

@MainActor
final class AppSession {
    let container: ModelContainer
    let purchases: PurchaseManager
    let app: AppModel

    init(container: ModelContainer, purchases: PurchaseManager, app: AppModel) {
        self.container = container
        self.purchases = purchases
        self.app = app
    }
}

enum LibraryStore {
    static func makeContainer() throws -> ModelContainer {
        let schema = persistentSchema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Deletes the on-disk SwiftData store so the next open starts clean.
    static func reset() {
        let configuration = ModelConfiguration(schema: persistentSchema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        let url = configuration.url
        let files = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm")
        ]
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Booleans only. Secret values stay out of the log.
    static func logReleaseConfiguration() {
        print("[Jojo] config revenueCat=\(Secrets.isRevenueCatConfigured) supabase=\(Secrets.isSupabaseConfigured) meta=\(Secrets.isMetaConfigured)")
    }

    private static var persistentSchema: Schema {
        Schema([SavedWord.self, CachedExplanation.self, UserProfile.self, RemoteClip.self, CustomDeck.self])
    }
}

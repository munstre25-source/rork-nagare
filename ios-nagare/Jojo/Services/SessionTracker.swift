import SwiftUI
import UIKit

/// Measures sessions and *active* time. Background time never counts, and foreground time only
/// counts while the learner is actually doing something (a touch or playback in the last 60s).
@MainActor
final class SessionTracker {
    static let shared = SessionTracker()

    /// Leaving the app for longer than this starts a new session.
    static let sessionGap: TimeInterval = 30 * 60
    /// Foreground time without a touch or playback for longer than this is idle, not active.
    static let idleCutoff: TimeInterval = 60
    static let tick: TimeInterval = 5

    private(set) var sessionId: String?
    private var startedAt = Date()
    private var activeSeconds: Double = 0
    private var lastActivity = Date.distantPast
    private var backgroundedAt: Date?
    private var timer: Timer?
    private var isForeground = false

    private var deviceClass: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: "tablet"
        case .mac: "mac"
        default: "phone"
        }
    }

    func setPhase(_ phase: ScenePhase) {
        switch phase {
        case .active: becameActive()
        case .background: enteredBackground()
        default: break
        }
    }

    /// Any touch, scroll or playback tick.
    func noteActivity() {
        lastActivity = Date()
    }

    /// Consent turned off: stop now. Turned on: start a fresh session.
    func consentChanged() {
        if AnalyticsConsent.isEnabled {
            sessionId = nil
            if isForeground { becameActive() }
        } else {
            timer?.invalidate()
            timer = nil
            sessionId = nil
        }
    }

    private func becameActive() {
        isForeground = true
        lastActivity = Date()
        guard AnalyticsConsent.isEnabled else { return }
        let resumedRecently = backgroundedAt.map { Date().timeIntervalSince($0) < Self.sessionGap } ?? false
        if sessionId == nil || !resumedRecently {
            startSession()
        }
        backgroundedAt = nil
        startTimer()
    }

    private func startSession() {
        let id = UUID().uuidString.lowercased()
        sessionId = id
        startedAt = Date()
        activeSeconds = 0
        Task { await AnalyticsUploader.shared.setCurrentSession(id) }
        track("session_start", props: ["device": deviceClass])
        pushSnapshot()
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.tick, repeats: true) { _ in
            MainActor.assumeIsolated { SessionTracker.shared.onTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func onTick() {
        guard isForeground, AnalyticsConsent.isEnabled, sessionId != nil else { return }
        if Date().timeIntervalSince(lastActivity) <= Self.idleCutoff {
            activeSeconds += Self.tick
        }
        pushSnapshot()
        Task { await AnalyticsUploader.shared.flushIfDue() }
    }

    private func enteredBackground() {
        isForeground = false
        timer?.invalidate()
        timer = nil
        guard AnalyticsConsent.isEnabled, sessionId != nil else { return }
        backgroundedAt = Date()
        pushSnapshot()
        // A short background task so the final snapshot and queued events get uploaded.
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "analytics-flush") {
            UIApplication.shared.endBackgroundTask(taskId)
            taskId = .invalid
        }
        Task {
            await AnalyticsUploader.shared.flush()
            if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
        }
    }

    private func pushSnapshot() {
        guard let sessionId else { return }
        let snapshot = SessionSnapshot(
            id: sessionId,
            startedAt: startedAt,
            lastSeenAt: Date(),
            activeSeconds: Int(activeSeconds),
            deviceClass: deviceClass
        )
        Task { await AnalyticsUploader.shared.upsertSession(snapshot) }
    }
}

/// Observes touches anywhere in the window without consuming them, so taps, scrolls and
/// gestures keep working exactly as before. Only the fact that a touch happened is recorded.
struct ActivityTouchObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ uiView: ObserverView, context: Context) {}

    final class ObserverView: UIView {
        private var installed: PassthroughTouchRecognizer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, installed == nil else { return }
            let recognizer = PassthroughTouchRecognizer()
            window.addGestureRecognizer(recognizer)
            installed = recognizer
        }
    }
}

final class PassthroughTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        SessionTracker.shared.noteActivity()
        state = .failed
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

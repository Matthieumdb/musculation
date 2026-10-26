import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Receives the running workout from the iPhone and sends the taps back.
@MainActor
@Observable
final class WatchSession: NSObject {
    static let shared = WatchSession()

    private(set) var workout: LiveWorkout?
    private(set) var templates: [String] = []
    private(set) var isPhoneReachable = false
    @ObservationIgnored private var restAlarm: Task<Void, Never>?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WatchCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        WKInterfaceDevice.current().play(.click)
        let message = [WatchKeys.command: data]
        if case .start = command {
            // Starting must not be lost: queue it if the iPhone cannot be reached right now
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(message)
            }
        } else {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    fileprivate func receiveTemplates(_ names: [String]?) {
        if let names { templates = names }
    }

    fileprivate func receive(_ data: Data?) {
        let decoded = data.flatMap { $0.isEmpty ? nil : try? JSONDecoder().decode(LiveWorkout.self, from: $0) }
        workout = decoded
        scheduleRestAlarm(decoded?.restEnd)
    }

    fileprivate func setReachable(_ reachable: Bool) {
        isPhoneReachable = reachable
    }

    /// Taps the wrist when the rest is over, while the app is on screen.
    private func scheduleRestAlarm(_ end: Date?) {
        restAlarm?.cancel()
        guard let end, end > .now else { return }
        restAlarm = Task {
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[WatchKeys.workout] as? Data
        let templates = session.receivedApplicationContext[WatchKeys.templates] as? [String]
        let reachable = session.isReachable
        Task { @MainActor in
            self.receive(data)
            self.receiveTemplates(templates)
            self.setReachable(reachable)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchKeys.workout] as? Data
        let templates = applicationContext[WatchKeys.templates] as? [String]
        Task { @MainActor in
            self.receive(data)
            self.receiveTemplates(templates)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[WatchKeys.workout] != nil else { return }
        let data = message[WatchKeys.workout] as? Data
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.setReachable(reachable) }
    }
}

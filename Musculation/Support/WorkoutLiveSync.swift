import ActivityKit
import Combine
import Foundation
import WatchConnectivity

/// Publishes the running workout to the Apple Watch and to the Live Activity,
/// and passes the watch's taps back to the workout screen.
@MainActor
final class WorkoutLiveSync: NSObject {
    static let shared = WorkoutLiveSync()

    /// Taps made on the watch, applied by `ActiveWorkoutView`.
    let commands = PassthroughSubject<WatchCommand, Never>()

    private var activity: Activity<WorkoutActivityAttributes>?
    private var last: LiveWorkout?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ workout: LiveWorkout) {
        guard workout != last else { return }
        last = workout
        sendToWatch(workout)
        updateActivity(workout)
    }

    func end() {
        last = nil
        sendToWatch(nil)
        let activity = activity
        self.activity = nil
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
        // An activity left over from a previous launch
        for leftover in Activity<WorkoutActivityAttributes>.activities {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: Watch

    private func sendToWatch(_ workout: LiveWorkout?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let data = workout.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        try? WCSession.default.updateApplicationContext([WatchKeys.workout: data])
        if WCSession.default.isReachable {
            WCSession.default.sendMessage([WatchKeys.workout: data], replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: Live Activity

    private func updateActivity(_ workout: LiveWorkout) {
        let state = Self.state(for: workout)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
            return
        }
        if let existing = Activity<WorkoutActivityAttributes>.activities.first {
            activity = existing
            Task { await existing.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: WorkoutActivityAttributes(title: workout.title, startedAt: workout.startedAt),
            content: content
        )
    }

    private static func state(for workout: LiveWorkout) -> WorkoutActivityAttributes.ContentState {
        var exercise = "Séance terminée ?"
        var detail = "Toutes les séries sont faites"
        if let position = workout.current {
            let e = workout.exercises[position.exercise]
            let s = e.sets[position.set]
            exercise = e.name
            detail = "Série \(position.set + 1)/\(e.sets.count) · \(s.weight.liveKgText) × \(s.reps)"
        } else if workout.totalSets == 0 {
            exercise = workout.title
            detail = "Ajoute un exercice"
        }
        let resting = workout.isResting
        return WorkoutActivityAttributes.ContentState(
            exercise: exercise,
            detail: detail,
            done: workout.doneSets,
            total: workout.totalSets,
            restStart: resting ? workout.restEnd?.addingTimeInterval(-workout.restTotal) : nil,
            restEnd: resting ? workout.restEnd : nil
        )
    }
}

extension WorkoutLiveSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let last = self.last { self.sendToWatch(last) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchKeys.command] as? Data,
              let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else { return }
        Task { @MainActor in self.commands.send(command) }
    }
}

extension Workout {
    /// Snapshot sent to the watch and the Live Activity.
    func live(restEnd: Date?, restTotal: TimeInterval) -> LiveWorkout {
        LiveWorkout(
            title: title,
            startedAt: startedAt,
            restEnd: restEnd,
            restTotal: restTotal,
            exercises: orderedExercises.map { entry in
                LiveWorkout.Exercise(
                    name: entry.exercise?.name ?? "Exercice",
                    sets: entry.orderedSets.map { LiveWorkout.Set(weight: $0.weight, reps: $0.reps, done: $0.isCompleted) }
                )
            }
        )
    }
}

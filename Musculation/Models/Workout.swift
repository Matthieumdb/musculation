import Foundation
import SwiftData

@Model
final class Workout {
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise] = []

    init(title: String, startedAt: Date = .now) {
        self.title = title
        self.startedAt = startedAt
        self.notes = ""
    }

    var orderedExercises: [WorkoutExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var totalVolume: Double { exercises.reduce(0) { $0 + $1.volume } }
    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }

    /// Adds an exercise, prefilled from the last time it was done (or from template targets).
    @discardableResult
    func addExercise(
        _ exercise: Exercise,
        targetSets: Int? = nil,
        targetReps: Int? = nil,
        in context: ModelContext
    ) -> WorkoutExercise {
        let previous = exercise.history.first?.orderedSets ?? []
        let entry = WorkoutExercise(order: (exercises.map(\.order).max() ?? -1) + 1)
        context.insert(entry)
        entry.exercise = exercise
        entry.workout = self

        let count = targetSets ?? max(previous.count, 1)
        for index in 0..<count {
            let reference = previous.isEmpty ? nil : previous[min(index, previous.count - 1)]
            entry.addSet(
                reps: targetReps ?? reference?.reps ?? 10,
                weight: reference?.weight ?? 0,
                in: context
            )
        }
        return entry
    }

    /// Ends the workout. Unchecked sets are dropped right after, once the
    /// active workout screen is gone, so no view reads a deleted model.
    func finish(in context: ModelContext) {
        endedAt = .now
        try? context.save()
        Task { @MainActor in
            self.pruneIncompleteSets(in: context)
        }
    }

    /// Discards the workout. Marked as ended first so the active screen goes away before deletion.
    func discard(in context: ModelContext) {
        endedAt = .now
        try? context.save()
        Task { @MainActor in
            context.delete(self)
            try? context.save()
        }
    }

    @MainActor
    private func pruneIncompleteSets(in context: ModelContext) {
        let kept = exercises.filter { $0.sets.contains(where: \.isCompleted) }
        let empty = exercises.filter { !$0.sets.contains(where: \.isCompleted) }

        if kept.isEmpty {
            context.delete(self)
        } else {
            empty.forEach { context.delete($0) }
            kept.flatMap { $0.sets.filter { !$0.isCompleted } }.forEach { context.delete($0) }
        }
        try? context.save()
    }
}

@Model
final class WorkoutExercise {
    var order: Int
    var workout: Workout?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet] = []

    init(order: Int) {
        self.order = order
    }

    var orderedSets: [WorkoutSet] { sets.sorted { $0.order < $1.order } }
    var maxWeight: Double { sets.map(\.weight).max() ?? 0 }
    var bestOneRepMax: Double { sets.map(\.estimatedOneRepMax).max() ?? 0 }
    var volume: Double { sets.reduce(0) { $0 + $1.volume } }
    var bestSet: WorkoutSet? { sets.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax } }

    /// "80 kg × 8 · 80 kg × 8 · 85 kg × 6"
    var summary: String {
        orderedSets.map { "\($0.weight.kgText) × \($0.reps)" }.joined(separator: " · ")
    }

    @discardableResult
    func addSet(reps: Int, weight: Double, in context: ModelContext) -> WorkoutSet {
        let set = WorkoutSet(order: (sets.map(\.order).max() ?? -1) + 1, reps: reps, weight: weight)
        context.insert(set)
        set.workoutExercise = self
        return set
    }
}

@Model
final class WorkoutSet {
    var order: Int
    var reps: Int
    var weight: Double
    var isCompleted: Bool
    var workoutExercise: WorkoutExercise?

    init(order: Int, reps: Int, weight: Double) {
        self.order = order
        self.reps = reps
        self.weight = weight
        self.isCompleted = false
    }

    var volume: Double { Double(reps) * weight }
    var estimatedOneRepMax: Double { OneRepMax.epley(weight: weight, reps: reps) }
}

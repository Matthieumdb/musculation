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
        minReps: Int? = nil,
        restSeconds: Int? = nil,
        note: String? = nil,
        allowProgression: Bool = true,
        in context: ModelContext
    ) -> WorkoutExercise {
        let previous = exercise.history.first?.orderedSets ?? []
        let entry = WorkoutExercise(order: (exercises.map(\.order).max() ?? -1) + 1)
        context.insert(entry)
        entry.exercise = exercise
        entry.workout = self
        entry.targetReps = targetReps
        entry.minReps = minReps
        entry.restSeconds = restSeconds
        entry.note = note

        // Each set aims a bit above the matching set of last time (see SetTarget).
        let range = SetTarget.repRange(minReps: minReps, targetReps: targetReps, previous: previous)
        let reference1RM = exercise.history.first.map(\.bestOneRepMax)
        var increment: Double = 0
        let count = targetSets ?? max(previous.count, 1)
        for index in 0..<count {
            let reference = previous.isEmpty ? nil : previous[min(index, previous.count - 1)]
            if let reference, reference.reps > 0 {
                let target = allowProgression
                    ? SetTarget.next(after: reference, range: range, exercise: exercise, oneRepMax: reference1RM)
                    : SetTarget(weight: reference.weight, reps: min(reference.reps, range.upperBound))
                increment = max(increment, target.weight - reference.weight)
                let set = entry.addSet(reps: target.reps, weight: target.weight, in: context)
                set.targetWeight = target.weight
                set.targetReps = target.reps
            } else {
                entry.addSet(reps: targetReps ?? 10, weight: 0, in: context)
            }
        }
        entry.progressionIncrement = increment > 0 ? increment : nil
        return entry
    }

    /// Swaps the exercise of an entry, prefilling the sets not done yet from the new exercise's last workout.
    func replace(_ entry: WorkoutExercise, with exercise: Exercise) {
        let previous = exercise.history.first?.orderedSets ?? []
        entry.exercise = exercise
        entry.progressionIncrement = nil
        let range = SetTarget.repRange(minReps: entry.minReps, targetReps: entry.targetReps, previous: previous)
        let reference1RM = exercise.history.first.map(\.bestOneRepMax)
        for (index, set) in entry.orderedSets.enumerated() where !set.isCompleted {
            guard !previous.isEmpty else {
                set.weight = 0
                set.targetWeight = nil
                set.targetReps = nil
                continue
            }
            let target = SetTarget.next(
                after: previous[min(index, previous.count - 1)],
                range: range,
                exercise: exercise,
                oneRepMax: reference1RM
            )
            set.weight = target.weight
            set.reps = target.reps
            set.targetWeight = target.weight
            set.targetReps = target.reps
        }
    }

    /// Templates with this workout's name that use `exercise`, so a swap can be kept for next time.
    func templates(using exercise: Exercise, in context: ModelContext) -> [WorkoutTemplate] {
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        return templates.filter { template in
            template.name == title
                && template.items.contains { $0.exercise?.persistentModelID == exercise.persistentModelID }
        }
    }

    /// Moves an exercise up (-1) or down (+1) in the workout.
    func move(_ entry: WorkoutExercise, by offset: Int) {
        var ordered = orderedExercises
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }),
              ordered.indices.contains(index + offset) else { return }
        ordered.swapAt(index, index + offset)
        for (position, item) in ordered.enumerated() {
            item.order = position
        }
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
    var targetReps: Int?
    var minReps: Int?
    var restSeconds: Int?
    var note: String?
    /// Weight added because the target reps were all reached last time.
    var progressionIncrement: Double?
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

    /// Best estimated 1RM before this workout, nil the first time the exercise is done.
    var previousBestOneRepMax: Double? {
        exercise?.history
            .filter { $0.workout?.persistentModelID != workout?.persistentModelID }
            .map(\.bestOneRepMax)
            .max()
    }

    /// "3 × 8-12 reps · repos 2 min 30"
    var targetDescription: String? {
        guard let targetReps else { return nil }
        let reps = minReps.map { "\($0)-\(targetReps)" } ?? "\(targetReps)"
        var text = "\(sets.count) × \(reps) reps"
        if let restSeconds {
            text += " · repos \(AppSettings.restLabel(restSeconds))"
        }
        return text
    }

    static func reachedTarget(_ sets: [WorkoutSet], targetReps: Int?) -> Bool {
        guard let targetReps, !sets.isEmpty else { return false }
        return sets.allSatisfy { $0.reps >= targetReps && $0.weight > 0 }
    }

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
    /// Rate of perceived exertion, 6 to 10 (10 = failure, 9 = one rep left…).
    var rpe: Double?
    /// Goal for this set, computed from the same set last time.
    var targetWeight: Double?
    var targetReps: Int?

    var reachedTarget: Bool {
        guard let targetReps else { return false }
        return weight >= (targetWeight ?? 0) && reps >= targetReps
    }
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

/// Per-set double progression: add reps up to the top of the range, then add weight and
/// go back to the bottom. An easy set (RPE 7 or less) moves up faster, a missed one holds.
struct SetTarget {
    let weight: Double
    let reps: Int

    static func repRange(minReps: Int?, targetReps: Int?, previous: [WorkoutSet]) -> ClosedRange<Int> {
        if let minReps, let targetReps, minReps <= targetReps { return minReps...targetReps }
        if let targetReps { return targetReps...targetReps }
        let typical = previous.map(\.reps).max() ?? 10
        switch typical {
        case ...6: return 4...6
        case 7...12: return 8...12
        default: return 12...20
        }
    }

    static func next(after set: WorkoutSet, range: ClosedRange<Int>, exercise: Exercise, oneRepMax: Double?) -> SetTarget {
        let weight = set.weight
        let reps = set.reps
        guard weight > 0 else {
            // Bodyweight: one more rep each time.
            return SetTarget(weight: 0, reps: reps + 1)
        }
        let effort = set.rpe ?? RPE.estimate(weight: weight, reps: reps, reference: oneRepMax)
        let increment = exercise.progressionIncrement(from: weight)

        if reps >= range.upperBound {
            return SetTarget(weight: weight + increment, reps: range.lowerBound)
        }
        if let effort, effort <= 7, reps >= range.lowerBound {
            // Plenty left in the tank: heavier, same reps.
            return SetTarget(weight: weight + increment, reps: reps)
        }
        if reps < range.lowerBound - 2 {
            // Clearly too heavy: step back to land in the range.
            return SetTarget(weight: max(0, weight - increment), reps: range.lowerBound)
        }
        if let effort, effort >= 10, reps < range.lowerBound {
            return SetTarget(weight: weight, reps: range.lowerBound)
        }
        return SetTarget(weight: weight, reps: min(reps + 1, range.upperBound))
    }
}

enum RPE {
    static let values: [Double] = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    static func label(_ rpe: Double) -> String {
        rpe.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Expected RPE of a set, from how many reps the reference 1RM allows at that weight (Epley).
    static func estimate(weight: Double, reps: Int, reference: Double?) -> Double? {
        guard let reference, reference > 0, weight > 0, reps > 0 else { return nil }
        let possibleReps = 30 * (reference / weight - 1)
        let inReserve = possibleReps - Double(reps)
        let rpe = (10 - inReserve) * 2
        return min(10, max(5, rpe.rounded() / 2))
    }

    static func meaning(_ rpe: Double) -> String {
        switch rpe {
        case 10: "Échec, plus aucune rep possible"
        case 9.5: "Peut-être une rep de plus"
        case 9: "1 rep en réserve"
        case 8.5: "1 à 2 reps en réserve"
        case 8: "2 reps en réserve"
        case 7.5: "2 à 3 reps en réserve"
        case 7: "3 reps en réserve"
        case 6.5: "3 à 4 reps en réserve"
        case 6: "4 reps en réserve"
        default: "5 reps ou plus en réserve"
        }
    }
}

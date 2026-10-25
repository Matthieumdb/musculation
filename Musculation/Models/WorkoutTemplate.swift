import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String
    var createdAt: Date
    /// Set when the template was installed from a built-in program.
    var programName: String?
    var programOrder: Int?

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var items: [TemplateExercise] = []

    init(name: String) {
        self.name = name
        self.createdAt = .now
    }

    var orderedItems: [TemplateExercise] { items.sorted { $0.order < $1.order } }

    var summary: String {
        orderedItems.compactMap { $0.exercise?.name }.joined(separator: " · ")
    }

    @discardableResult
    func addItem(_ exercise: Exercise, in context: ModelContext) -> TemplateExercise {
        let item = TemplateExercise(order: (items.map(\.order).max() ?? -1) + 1)
        context.insert(item)
        item.exercise = exercise
        item.template = self
        return item
    }

    /// Starts a workout from this template. A deload halves the sets and skips the weight increase.
    func startWorkout(in context: ModelContext, deload: Bool = false) {
        let workout = Workout(title: name)
        context.insert(workout)
        for item in orderedItems {
            guard let exercise = item.exercise else { continue }
            workout.addExercise(
                exercise,
                targetSets: deload ? max(1, (item.targetSets + 1) / 2) : item.targetSets,
                targetReps: item.targetReps,
                minReps: item.minReps,
                restSeconds: item.restSeconds,
                note: item.notes,
                allowProgression: !deload,
                in: context
            )
        }
        try? context.save()
    }
}

@Model
final class TemplateExercise {
    var order: Int
    var targetSets: Int
    /// Top of the rep range: once every set reaches it, the weight goes up.
    var targetReps: Int
    /// Bottom of the rep range, nil for a fixed rep target.
    var minReps: Int?
    var restSeconds: Int?
    var notes: String?
    var template: WorkoutTemplate?
    var exercise: Exercise?

    init(order: Int, targetSets: Int = 3, targetReps: Int = 10) {
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
    }
}

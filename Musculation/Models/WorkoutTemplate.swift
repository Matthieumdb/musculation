import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String
    var createdAt: Date

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

    func addItem(_ exercise: Exercise, in context: ModelContext) {
        let item = TemplateExercise(order: (items.map(\.order).max() ?? -1) + 1)
        context.insert(item)
        item.exercise = exercise
        item.template = self
    }

    func startWorkout(in context: ModelContext) {
        let workout = Workout(title: name)
        context.insert(workout)
        for item in orderedItems {
            guard let exercise = item.exercise else { continue }
            workout.addExercise(exercise, targetSets: item.targetSets, targetReps: item.targetReps, in: context)
        }
        try? context.save()
    }
}

@Model
final class TemplateExercise {
    var order: Int
    var targetSets: Int
    var targetReps: Int
    var template: WorkoutTemplate?
    var exercise: Exercise?

    init(order: Int, targetSets: Int = 3, targetReps: Int = 10) {
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
    }
}

import Foundation
import SwiftData

enum MuscleGroup: String, CaseIterable, Identifiable, Codable {
    case chest, back, shoulders, biceps, triceps, legs, glutes, abs, fullBody, cardio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Pectoraux"
        case .back: "Dos"
        case .shoulders: "Épaules"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .legs: "Jambes"
        case .glutes: "Fessiers"
        case .abs: "Abdos"
        case .fullBody: "Full body"
        case .cardio: "Cardio"
        }
    }
}

@Model
final class Exercise {
    var name: String
    var muscleGroupRaw: String
    var notes: String
    var createdAt: Date
    /// Smallest weight jump for this exercise, nil to use the equipment's default.
    var weightStep: Double?
    /// Id in the bundled exercise library, for exercises added from it.
    var libraryId: String?

    @Relationship(deleteRule: .nullify, inverse: \WorkoutExercise.exercise)
    var entries: [WorkoutExercise] = []

    @Relationship(deleteRule: .nullify, inverse: \TemplateExercise.exercise)
    var templateItems: [TemplateExercise] = []

    init(name: String, muscleGroup: MuscleGroup, notes: String = "") {
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.notes = notes
        self.createdAt = .now
    }

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
        set { muscleGroupRaw = newValue.rawValue }
    }

    /// Entries from finished workouts, most recent first.
    var history: [WorkoutExercise] {
        entries
            .filter { $0.workout?.endedAt != nil && !$0.sets.isEmpty }
            .sorted { ($0.workout?.startedAt ?? .distantPast) > ($1.workout?.startedAt ?? .distantPast) }
    }
}

struct ExerciseSection: Identifiable {
    let group: MuscleGroup
    let exercises: [Exercise]

    var id: MuscleGroup { group }

    static func make(from exercises: [Exercise], matching search: String = "") -> [ExerciseSection] {
        let filtered = search.isEmpty
            ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return MuscleGroup.allCases.compactMap { group in
            let items = filtered
                .filter { $0.muscleGroup == group }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return items.isEmpty ? nil : ExerciseSection(group: group, exercises: items)
        }
    }
}

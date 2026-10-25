import Foundation
import SwiftData

/// JSON backup of everything the user entered. Exercises are linked by name.
struct Backup: Codable {
    var version: Int
    var exportedAt: Date
    var exercises: [ExerciseRecord]
    var workouts: [WorkoutRecord]
    var templates: [TemplateRecord]
    var bodyWeights: [BodyWeightRecord]

    struct ExerciseRecord: Codable {
        var name: String
        var muscleGroup: String
        var notes: String
        var weightStep: Double?
    }

    struct SetRecord: Codable {
        var reps: Int
        var weight: Double
        var isCompleted: Bool
    }

    struct WorkoutExerciseRecord: Codable {
        var exercise: String?
        var targetReps: Int?
        var minReps: Int?
        var restSeconds: Int?
        var note: String?
        var sets: [SetRecord]
    }

    struct WorkoutRecord: Codable {
        var title: String
        var startedAt: Date
        var endedAt: Date?
        var notes: String
        var exercises: [WorkoutExerciseRecord]
    }

    struct TemplateItemRecord: Codable {
        var exercise: String?
        var targetSets: Int
        var targetReps: Int
        var minReps: Int?
        var restSeconds: Int?
        var notes: String?
    }

    struct TemplateRecord: Codable {
        var name: String
        var programName: String?
        var programOrder: Int?
        var items: [TemplateItemRecord]
    }

    struct BodyWeightRecord: Codable {
        var date: Date
        var weight: Double
    }
}

enum BackupService {
    static func makeBackup(from context: ModelContext) throws -> Backup {
        let exercises = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))
        let workouts = try context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt)]
        ))
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.createdAt)]))
        let bodyWeights = try context.fetch(FetchDescriptor<BodyWeightEntry>(sortBy: [SortDescriptor(\.date)]))

        return Backup(
            version: 1,
            exportedAt: .now,
            exercises: exercises.map {
                Backup.ExerciseRecord(name: $0.name, muscleGroup: $0.muscleGroupRaw, notes: $0.notes, weightStep: $0.weightStep)
            },
            workouts: workouts.map { workout in
                Backup.WorkoutRecord(
                    title: workout.title,
                    startedAt: workout.startedAt,
                    endedAt: workout.endedAt,
                    notes: workout.notes,
                    exercises: workout.orderedExercises.map { entry in
                        Backup.WorkoutExerciseRecord(
                            exercise: entry.exercise?.name,
                            targetReps: entry.targetReps,
                            minReps: entry.minReps,
                            restSeconds: entry.restSeconds,
                            note: entry.note,
                            sets: entry.orderedSets.map {
                                Backup.SetRecord(reps: $0.reps, weight: $0.weight, isCompleted: $0.isCompleted)
                            }
                        )
                    }
                )
            },
            templates: templates.map { template in
                Backup.TemplateRecord(
                    name: template.name,
                    programName: template.programName,
                    programOrder: template.programOrder,
                    items: template.orderedItems.map {
                        Backup.TemplateItemRecord(
                            exercise: $0.exercise?.name,
                            targetSets: $0.targetSets,
                            targetReps: $0.targetReps,
                            minReps: $0.minReps,
                            restSeconds: $0.restSeconds,
                            notes: $0.notes
                        )
                    }
                )
            },
            bodyWeights: bodyWeights.map { Backup.BodyWeightRecord(date: $0.date, weight: $0.weight) }
        )
    }

    /// Writes a backup to a temporary file ready to share.
    static func exportFile(from context: ModelContext) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(makeBackup(from: context))
        let day = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Musculation-\(day).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func read(_ url: URL) throws -> Backup {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: Data(contentsOf: url))
    }

    /// Replaces all data with the backup's content.
    static func restore(_ backup: Backup, into context: ModelContext) throws {
        try context.fetch(FetchDescriptor<Workout>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<WorkoutTemplate>()).forEach { context.delete($0) }
        try context.fetch(FetchDescriptor<BodyWeightEntry>()).forEach { context.delete($0) }
        try context.save()
        try context.fetch(FetchDescriptor<Exercise>()).forEach { context.delete($0) }
        try context.save()

        var exercisesByName: [String: Exercise] = [:]
        for record in backup.exercises where exercisesByName[record.name] == nil {
            let exercise = Exercise(
                name: record.name,
                muscleGroup: MuscleGroup(rawValue: record.muscleGroup) ?? .fullBody,
                notes: record.notes
            )
            context.insert(exercise)
            exercise.weightStep = record.weightStep
            exercisesByName[record.name] = exercise
        }

        for record in backup.workouts {
            let workout = Workout(title: record.title, startedAt: record.startedAt)
            context.insert(workout)
            workout.endedAt = record.endedAt ?? record.startedAt
            workout.notes = record.notes
            for (index, entryRecord) in record.exercises.enumerated() {
                let entry = WorkoutExercise(order: index)
                context.insert(entry)
                entry.workout = workout
                entry.exercise = entryRecord.exercise.flatMap { exercisesByName[$0] }
                entry.targetReps = entryRecord.targetReps
                entry.minReps = entryRecord.minReps
                entry.restSeconds = entryRecord.restSeconds
                entry.note = entryRecord.note
                for setRecord in entryRecord.sets {
                    let set = entry.addSet(reps: setRecord.reps, weight: setRecord.weight, in: context)
                    set.isCompleted = setRecord.isCompleted
                }
            }
        }

        for record in backup.templates {
            let template = WorkoutTemplate(name: record.name)
            context.insert(template)
            template.programName = record.programName
            template.programOrder = record.programOrder
            for itemRecord in record.items {
                guard let exercise = itemRecord.exercise.flatMap({ exercisesByName[$0] }) else { continue }
                let item = template.addItem(exercise, in: context)
                item.targetSets = itemRecord.targetSets
                item.targetReps = itemRecord.targetReps
                item.minReps = itemRecord.minReps
                item.restSeconds = itemRecord.restSeconds
                item.notes = itemRecord.notes
            }
        }

        for record in backup.bodyWeights {
            context.insert(BodyWeightEntry(date: record.date, weight: record.weight))
        }

        try context.save()
    }
}

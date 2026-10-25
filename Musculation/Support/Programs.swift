import Foundation
import SwiftData

struct ProgramExercise {
    let name: String
    let group: MuscleGroup
    let sets: Int
    let minReps: Int
    let maxReps: Int
    let rest: Int
    var note: String? = nil
}

struct ProgramSession: Identifiable {
    let name: String
    let day: String
    let exercises: [ProgramExercise]

    var id: String { name }
}

struct ProgramPhase {
    let week: Int
    let title: String
    let detail: String
    let isDeload: Bool
}

struct TrainingProgram {
    let name: String
    let summary: String
    let sessions: [ProgramSession]
    let rules: [String]

    static let cycleWeeks = 8
    static let startDateKey = "programStartDate"

    /// Week of the 8-week cycle and what it asks for.
    static func phase(startedAt start: Date, now: Date = .now) -> ProgramPhase {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        let week = (max(0, days) / 7) % cycleWeeks + 1
        switch week {
        case 1...2:
            return ProgramPhase(week: week, title: "Reprise", detail: "Garde 2 à 3 répétitions en réserve.", isDeload: false)
        case 3...6:
            return ProgramPhase(week: week, title: "Progression", detail: "1 à 2 répétitions en réserve, dernière série des isolations à l'échec.", isDeload: false)
        case 7:
            return ProgramPhase(week: week, title: "Surcharge", detail: "Ajoute 1 série sur 1 ou 2 muscles en retard.", isDeload: false)
        default:
            return ProgramPhase(week: week, title: "Décharge", detail: "Moitié des séries, 3 à 4 répétitions en réserve.", isDeload: true)
        }
    }

    /// Replaces any previous copy of this program's templates and restarts the cycle.
    func install(in context: ModelContext) {
        Self.templates(of: name, in: context).forEach { context.delete($0) }

        var exercisesByName: [String: Exercise] = [:]
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] where exercisesByName[exercise.name.lowercased()] == nil {
            exercisesByName[exercise.name.lowercased()] = exercise
        }

        for (index, session) in sessions.enumerated() {
            let template = WorkoutTemplate(name: session.name)
            context.insert(template)
            template.programName = name
            template.programOrder = index
            for programExercise in session.exercises {
                let key = programExercise.name.lowercased()
                let exercise: Exercise
                if let existing = exercisesByName[key] {
                    exercise = existing
                } else {
                    exercise = Exercise(name: programExercise.name, muscleGroup: programExercise.group)
                    context.insert(exercise)
                    exercisesByName[key] = exercise
                }
                let item = template.addItem(exercise, in: context)
                item.targetSets = programExercise.sets
                item.minReps = programExercise.minReps
                item.targetReps = programExercise.maxReps
                item.restSeconds = programExercise.rest
                item.notes = programExercise.note
            }
        }

        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.startDateKey)
        try? context.save()
    }

    static func templates(of programName: String, in context: ModelContext) -> [WorkoutTemplate] {
        let all = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        return all.filter { $0.programName == programName }
    }

    static func uninstall(_ programName: String, in context: ModelContext) {
        templates(of: programName, in: context).forEach { context.delete($0) }
        UserDefaults.standard.removeObject(forKey: startDateKey)
        try? context.save()
    }
}

extension TrainingProgram {
    private static let noFailure = "Pas d'échec : garde 1 à 2 reps en réserve."
    private static let lastSetToFailure = "Dernière série à l'échec."

    static let hypertrophy5 = TrainingProgram(
        name: "Hypertrophie 5 séances",
        summary: "Upper / Lower / Push / Pull / Legs. Chaque muscle 2 fois par semaine, 12 à 16 séries dures par muscle, double progression et décharge toutes les 8 semaines.",
        sessions: [
            ProgramSession(name: "Upper", day: "Lundi", exercises: [
                ProgramExercise(name: "Développé couché", group: .chest, sets: 3, minReps: 6, maxReps: 8, rest: 180, note: noFailure),
                ProgramExercise(name: "Rowing poitrine appuyée", group: .back, sets: 3, minReps: 8, maxReps: 10, rest: 150),
                ProgramExercise(name: "Développé incliné haltères", group: .chest, sets: 2, minReps: 8, maxReps: 12, rest: 120),
                ProgramExercise(name: "Tirage vertical prise neutre", group: .back, sets: 3, minReps: 8, maxReps: 12, rest: 120),
                ProgramExercise(name: "Élévations latérales", group: .shoulders, sets: 3, minReps: 12, maxReps: 20, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Curl barre EZ", group: .biceps, sets: 2, minReps: 8, maxReps: 12, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Extension triceps au-dessus de la tête", group: .triceps, sets: 2, minReps: 10, maxReps: 15, rest: 90, note: "À la poulie. Dernière série à l'échec."),
            ]),
            ProgramSession(name: "Lower", day: "Mardi", exercises: [
                ProgramExercise(name: "Squat", group: .legs, sets: 3, minReps: 6, maxReps: 8, rest: 180, note: noFailure),
                ProgramExercise(name: "Soulevé de terre roumain", group: .glutes, sets: 3, minReps: 8, maxReps: 10, rest: 150, note: noFailure),
                ProgramExercise(name: "Leg extension", group: .legs, sets: 3, minReps: 10, maxReps: 15, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Leg curl assis", group: .legs, sets: 3, minReps: 10, maxReps: 15, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Mollets debout", group: .legs, sets: 3, minReps: 8, maxReps: 12, rest: 90, note: "Pause d'une seconde en bas."),
                ProgramExercise(name: "Crunch poulie", group: .abs, sets: 3, minReps: 10, maxReps: 15, rest: 60),
            ]),
            ProgramSession(name: "Push", day: "Jeudi", exercises: [
                ProgramExercise(name: "Développé incliné machine", group: .chest, sets: 3, minReps: 8, maxReps: 10, rest: 150, note: "Smith ou machine."),
                ProgramExercise(name: "Développé épaules", group: .shoulders, sets: 2, minReps: 8, maxReps: 12, rest: 120),
                ProgramExercise(name: "Pec deck", group: .chest, sets: 3, minReps: 12, maxReps: 15, rest: 90, note: "Ou écarté à la poulie. Dernière série à l'échec."),
                ProgramExercise(name: "Élévations latérales", group: .shoulders, sets: 3, minReps: 12, maxReps: 20, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Dips", group: .chest, sets: 2, minReps: 8, maxReps: 12, rest: 120),
                ProgramExercise(name: "Pushdown triceps", group: .triceps, sets: 3, minReps: 10, maxReps: 15, rest: 90, note: lastSetToFailure),
            ]),
            ProgramSession(name: "Pull", day: "Vendredi", exercises: [
                ProgramExercise(name: "Tractions", group: .back, sets: 3, minReps: 6, maxReps: 10, rest: 150, note: "Lestées si besoin pour rester dans la fourchette."),
                ProgramExercise(name: "Rowing assis poulie", group: .back, sets: 3, minReps: 8, maxReps: 12, rest: 120),
                ProgramExercise(name: "Pull-over poulie", group: .back, sets: 2, minReps: 10, maxReps: 15, rest: 90),
                ProgramExercise(name: "Oiseau (reverse pec deck)", group: .shoulders, sets: 3, minReps: 12, maxReps: 20, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Curl incliné haltères", group: .biceps, sets: 3, minReps: 10, maxReps: 15, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Curl marteau", group: .biceps, sets: 2, minReps: 10, maxReps: 15, rest: 90, note: lastSetToFailure),
            ]),
            ProgramSession(name: "Legs", day: "Samedi", exercises: [
                ProgramExercise(name: "Presse à cuisses", group: .legs, sets: 3, minReps: 10, maxReps: 15, rest: 150),
                ProgramExercise(name: "Fentes bulgares", group: .legs, sets: 2, minReps: 8, maxReps: 12, rest: 120, note: "Reps par jambe."),
                ProgramExercise(name: "Leg curl allongé", group: .legs, sets: 3, minReps: 10, maxReps: 15, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Hip thrust", group: .glutes, sets: 2, minReps: 8, maxReps: 12, rest: 120),
                ProgramExercise(name: "Leg extension", group: .legs, sets: 2, minReps: 12, maxReps: 15, rest: 90, note: lastSetToFailure),
                ProgramExercise(name: "Mollets assis", group: .legs, sets: 3, minReps: 12, maxReps: 15, rest: 90),
                ProgramExercise(name: "Adducteurs machine", group: .legs, sets: 2, minReps: 12, maxReps: 15, rest: 60),
            ]),
        ],
        rules: [
            "Toutes les séries à 1 ou 2 répétitions de l'échec (RIR 1-2).",
            "Pas d'échec sur le squat, le soulevé de terre roumain et le développé couché lourd.",
            "Double progression : monte les reps jusqu'au haut de la fourchette sur toutes les séries, puis augmente la charge. L'app le fait pour toi.",
            "Semaine type : lundi Upper, mardi Lower, jeudi Push, vendredi Pull, samedi Legs.",
        ]
    )

    static let all = [hypertrophy5]
}

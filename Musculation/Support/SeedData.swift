import Foundation
import SwiftData

enum SeedData {
    private static let seededKey = "didSeedExercises"

    private static let exercises: [(String, MuscleGroup)] = [
        ("Développé couché", .chest),
        ("Développé incliné haltères", .chest),
        ("Écarté à la poulie", .chest),
        ("Dips", .chest),
        ("Tractions", .back),
        ("Rowing barre", .back),
        ("Tirage vertical", .back),
        ("Rowing haltère", .back),
        ("Soulevé de terre", .back),
        ("Développé militaire", .shoulders),
        ("Élévations latérales", .shoulders),
        ("Face pull", .shoulders),
        ("Curl barre", .biceps),
        ("Curl marteau", .biceps),
        ("Extension triceps poulie", .triceps),
        ("Barre au front", .triceps),
        ("Squat", .legs),
        ("Presse à cuisses", .legs),
        ("Fentes", .legs),
        ("Leg curl", .legs),
        ("Leg extension", .legs),
        ("Mollets debout", .legs),
        ("Soulevé de terre roumain", .glutes),
        ("Hip thrust", .glutes),
        ("Gainage", .abs),
        ("Crunch", .abs),
    ]

    static func insertDefaultExercisesIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        if existing == 0 {
            for (name, group) in exercises {
                context.insert(Exercise(name: name, muscleGroup: group))
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}

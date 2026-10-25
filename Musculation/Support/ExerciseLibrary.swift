import SwiftUI

/// One exercise from Free Exercise DB (public domain), bundled as exercise-library.json.
struct LibraryExercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let nameFR: String
    let equipment: String
    let level: String
    let primary: [String]
    let secondary: [String]
    let instructions: [String]
    let mechanic: String?
    let instructionsFR: [String]?

    var hasFrenchInstructions: Bool { instructionsFR != nil }
    var displayInstructions: [String] { instructionsFR ?? instructions }

    var muscleGroup: MuscleGroup {
        switch primary.first {
        case "chest": .chest
        case "lats", "middle back", "lower back", "traps": .back
        case "shoulders", "neck": .shoulders
        case "biceps", "forearms": .biceps
        case "triceps": .triceps
        case "glutes": .glutes
        case "abdominals": .abs
        default: .legs
        }
    }

    var appEquipment: Equipment? {
        switch equipment {
        case "barbell", "e-z curl bar": .barbell
        case "dumbbell", "kettlebells": .dumbbell
        case "cable": .cable
        case "machine": .machine
        case "body only": .bodyweight
        default: nil
        }
    }

    var equipmentLabel: String { ExerciseLibrary.equipmentLabel(equipment) }
    var primaryLabel: String { primary.map(ExerciseLibrary.muscleLabel).joined(separator: ", ") }

    var levelLabel: String {
        switch level {
        case "beginner": "Débutant"
        case "intermediate": "Intermédiaire"
        default: "Avancé"
        }
    }

    func matches(_ search: String) -> Bool {
        search.isEmpty
            || nameFR.localizedStandardContains(search)
            || name.localizedStandardContains(search)
    }
}

enum ExerciseLibrary {
    static let all: [LibraryExercise] = {
        guard let url = Bundle.main.url(forResource: "exercise-library", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([LibraryExercise].self, from: data)
        else { return [] }
        return items
    }()

    private static let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    private static let byFrenchName = Dictionary(
        all.map { ($0.nameFR.lowercased(), $0) }, uniquingKeysWith: { first, _ in first }
    )

    /// The app's built-in and program exercises, matched to their library entry.
    private static let builtInIds: [String: String] = [
        "Développé couché": "Barbell_Bench_Press_-_Medium_Grip",
        "Développé incliné haltères": "Incline_Dumbbell_Press",
        "Écarté à la poulie": "Flat_Bench_Cable_Flyes",
        "Dips": "Dips_-_Chest_Version",
        "Tractions": "Pullups",
        "Rowing barre": "Bent_Over_Barbell_Row",
        "Tirage vertical": "Wide-Grip_Lat_Pulldown",
        "Rowing haltère": "One-Arm_Dumbbell_Row",
        "Soulevé de terre": "Barbell_Deadlift",
        "Développé militaire": "Standing_Military_Press",
        "Élévations latérales": "Side_Lateral_Raise",
        "Face pull": "Face_Pull",
        "Curl barre": "Barbell_Curl",
        "Curl marteau": "Hammer_Curls",
        "Extension triceps poulie": "Triceps_Pushdown",
        "Barre au front": "EZ-Bar_Skullcrusher",
        "Squat": "Barbell_Squat",
        "Presse à cuisses": "Leg_Press",
        "Fentes": "Dumbbell_Lunges",
        "Leg curl": "Lying_Leg_Curls",
        "Leg extension": "Leg_Extensions",
        "Mollets debout": "Standing_Calf_Raises",
        "Soulevé de terre roumain": "Romanian_Deadlift",
        "Hip thrust": "Barbell_Hip_Thrust",
        "Gainage": "Plank",
        "Crunch": "Crunches",
        "Rowing poitrine appuyée": "Dumbbell_Incline_Row",
        "Tirage vertical prise neutre": "V-Bar_Pulldown",
        "Curl barre EZ": "EZ-Bar_Curl",
        "Extension triceps au-dessus de la tête": "Cable_Rope_Overhead_Triceps_Extension",
        "Leg curl assis": "Seated_Leg_Curl",
        "Crunch poulie": "Cable_Crunch",
        "Développé incliné machine": "Smith_Machine_Incline_Bench_Press",
        "Développé épaules": "Dumbbell_Shoulder_Press",
        "Pec deck": "Butterfly",
        "Pushdown triceps": "Triceps_Pushdown_-_Rope_Attachment",
        "Rowing assis poulie": "Seated_Cable_Rows",
        "Pull-over poulie": "Straight-Arm_Pulldown",
        "Oiseau (reverse pec deck)": "Reverse_Machine_Flyes",
        "Curl incliné haltères": "Incline_Dumbbell_Curl",
        "Fentes bulgares": "Split_Squat_with_Dumbbells",
        "Leg curl allongé": "Lying_Leg_Curls",
        "Mollets assis": "Seated_Calf_Raise",
        "Adducteurs machine": "Thigh_Adductor",
    ]

    static func entry(id: String) -> LibraryExercise? { byId[id] }

    static func entry(for exercise: Exercise) -> LibraryExercise? {
        if let id = exercise.libraryId, let entry = byId[id] { return entry }
        if let id = builtInIds[exercise.name] { return byId[id] }
        return byFrenchName[exercise.name.lowercased()]
    }

    /// Muscles used as primary muscle, in display order.
    static let muscles: [String] = [
        "chest", "lats", "middle back", "lower back", "traps", "shoulders", "biceps", "triceps",
        "forearms", "abdominals", "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors", "neck",
    ]

    static let equipments: [String] = [
        "barbell", "dumbbell", "machine", "cable", "body only", "e-z curl bar",
        "kettlebells", "bands", "exercise ball", "medicine ball", "other",
    ]

    static func muscleLabel(_ muscle: String) -> String {
        switch muscle {
        case "abdominals": "Abdominaux"
        case "abductors": "Abducteurs"
        case "adductors": "Adducteurs"
        case "biceps": "Biceps"
        case "calves": "Mollets"
        case "chest": "Pectoraux"
        case "forearms": "Avant-bras"
        case "glutes": "Fessiers"
        case "hamstrings": "Ischio-jambiers"
        case "lats": "Grand dorsal"
        case "lower back": "Lombaires"
        case "middle back": "Milieu du dos"
        case "neck": "Cou"
        case "quadriceps": "Quadriceps"
        case "shoulders": "Épaules"
        case "traps": "Trapèzes"
        case "triceps": "Triceps"
        default: muscle.capitalized
        }
    }

    static func equipmentLabel(_ equipment: String) -> String {
        switch equipment {
        case "barbell": "Barre"
        case "dumbbell": "Haltères"
        case "machine": "Machine"
        case "cable": "Poulie"
        case "body only": "Poids du corps"
        case "e-z curl bar": "Barre EZ"
        case "kettlebells": "Kettlebell"
        case "bands": "Élastiques"
        case "exercise ball": "Swiss ball"
        case "medicine ball": "Médecine-ball"
        default: "Autre"
        }
    }
}

/// Exercise photos: bundled for the built-in exercises, otherwise downloaded once and cached.
enum ExerciseImageStore {
    private static let memory = NSCache<NSString, UIImage>()

    private static func fileName(_ id: String, _ frame: Int) -> String { "exo_\(id)_\(frame)" }

    private static func cacheURL(_ id: String, _ frame: Int) -> URL {
        URL.cachesDirectory.appending(path: fileName(id, frame) + ".jpg")
    }

    private static func remoteURL(_ id: String, _ frame: Int) -> URL? {
        URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\(id)/\(frame).jpg")
    }

    /// Image available without network, if any.
    static func cached(_ id: String, frame: Int) -> UIImage? {
        let key = fileName(id, frame) as NSString
        if let image = memory.object(forKey: key) { return image }
        let local = Bundle.main.url(forResource: fileName(id, frame), withExtension: "jpg") ?? cacheURL(id, frame)
        guard let image = UIImage(contentsOfFile: local.path) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    static func load(_ id: String, frame: Int) async -> UIImage? {
        if let image = cached(id, frame: frame) { return image }
        guard let url = remoteURL(id, frame),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data)
        else { return nil }
        try? data.write(to: cacheURL(id, frame))
        memory.setObject(image, forKey: fileName(id, frame) as NSString)
        return image
    }
}

extension Exercise {
    var libraryEntry: LibraryExercise? { ExerciseLibrary.entry(for: self) }
}

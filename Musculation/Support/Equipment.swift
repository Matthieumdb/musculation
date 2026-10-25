import Foundation

/// Kind of equipment, which sets the smallest weight jump available.
enum Equipment: String, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell: "barre"
        case .dumbbell: "haltères"
        case .machine: "machine"
        case .cable: "poulie"
        case .bodyweight: "poids du corps"
        }
    }

    /// Smallest common jump in a typical gym.
    var defaultStep: Double {
        switch self {
        case .barbell: 2.5      // 1,25 kg de chaque côté
        case .dumbbell: 2       // paire suivante au rack
        case .machine: 5        // une plaque de pile ou 2 × 2,5 kg
        case .cable: 2.5        // une plaque de pile
        case .bodyweight: 2.5   // lest
        }
    }

    static let stepOptions: [Double] = [0.5, 1, 1.25, 2, 2.5, 5, 10]

    /// Best guess from the exercise name.
    static func infer(from name: String) -> Equipment {
        let name = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }

        if has("haltère") { return .dumbbell }
        if has("poulie", "pushdown", "face pull", "tirage", "pull-over", "extension triceps") { return .cable }
        if has("machine", "presse", "leg extension", "leg curl", "pec deck", "mollets", "adducteur", "abducteur", "smith") { return .machine }
        if has("traction", "dips", "gainage", "crunch", "pompes") { return .bodyweight }
        if has("élévations", "curl marteau", "fentes", "appuyée", "oiseau") { return .dumbbell }
        return .barbell
    }
}

extension Exercise {
    var equipment: Equipment {
        if libraryId != nil, let equipment = libraryEntry?.appEquipment { return equipment }
        return Equipment.infer(from: name)
    }

    /// The exercise's own smallest jump, or the equipment's default.
    var effectiveWeightStep: Double { weightStep ?? equipment.defaultStep }

    /// Weight to add once the target reps are reached: about `AppSettings.progressionPercent`
    /// of the current weight, rounded to the nearest available jump, and at least one jump.
    func progressionIncrement(from weight: Double) -> Double {
        let step = effectiveWeightStep
        guard step > 0 else { return 0 }
        let target = weight * AppSettings.progressionPercent / 100
        return max(step, (target / step).rounded() * step)
    }
}

import SwiftUI
import SwiftData

/// Bevel-style readiness: muscle freshness from recent sets, and a daily recovery score
/// from how you slept and feel. Simple, explainable rules, not a medical measure.
enum Recovery {
    struct Muscle: Identifiable {
        var group: MuscleGroup
        /// 0 (just trained hard) to 1 (fully rested)
        var freshness: Double
        var id: MuscleGroup { group }
    }

    struct Score {
        var value: Int
        /// False when no check-in was made: the score only follows the training.
        var isComplete: Bool
        var factors: [String]

        var verdict: String {
            switch value {
            case 75...: "Prêt pour une grosse séance"
            case 50..<75: "Séance modérée conseillée"
            default: "Plutôt repos ou mobilité"
            }
        }

        var tint: Color {
            switch value {
            case 75...: .green
            case 50..<75: .orange
            default: .red
            }
        }
    }

    static let trackedGroups: [MuscleGroup] = MuscleGroup.allCases.filter { $0 != .cardio && $0 != .fullBody }

    /// Each working set tires its muscle for about 72 hours; 12 recent sets leave it at 0 %.
    static func freshness(_ workouts: [Workout], now: Date = .now) -> [Muscle] {
        var fatigue: [MuscleGroup: Double] = [:]
        for workout in workouts where workout.endedAt != nil && workout.startedAt <= now {
            let hours = now.timeIntervalSince(workout.startedAt) / 3600
            guard hours < 72 else { continue }
            let weight = 1 - hours / 72
            for entry in workout.exercises {
                guard let group = entry.exercise?.muscleGroup else { continue }
                let sets = Double(entry.sets.filter { $0.isCompleted && $0.kind != .warmup }.count)
                if group == .fullBody {
                    for g in trackedGroups { fatigue[g, default: 0] += sets * weight * 0.3 }
                } else if group != .cardio {
                    fatigue[group, default: 0] += sets * weight
                }
            }
        }
        return trackedGroups.map { Muscle(group: $0, freshness: max(0, 1 - (fatigue[$0] ?? 0) / 12)) }
    }

    static func score(_ checkIn: DailyCheckIn?, muscles: [Muscle]) -> Score {
        var value = 75.0
        var factors: [String] = []
        let tired = muscles.filter { $0.freshness < 0.6 }
        let average = muscles.isEmpty ? 1 : muscles.reduce(0) { $0 + $1.freshness } / Double(muscles.count)
        value += (average - 0.85) * 40
        if !tired.isEmpty {
            factors.append("\(tired.count) muscle\(tired.count > 1 ? "s" : "") encore fatigué\(tired.count > 1 ? "s" : "")")
        }

        guard let c = checkIn, c.hasFeelings else {
            return Score(value: Int(min(100, max(1, value)).rounded()), isComplete: false, factors: factors)
        }
        if let h = c.sleepHours {
            value += min(8, max(-20, (h - 7.5) * 6))
            if h < 6.5 { factors.append("nuit courte") } else if h >= 7.5 { factors.append("bonne nuit") }
        }
        if let q = c.sleepQuality { value += Double(q - 3) * 5 }
        if let e = c.energy {
            value += Double(e - 3) * 5
            if e <= 2 { factors.append("peu d'énergie") }
        }
        if let s = c.soreness {
            value -= Double(s - 1) * 5
            if s >= 4 { factors.append("courbatures") }
        }
        if let t = c.stress {
            value -= Double(t - 1) * 4
            if t >= 4 { factors.append("stress élevé") }
        }
        if c.alcohol > 0 {
            value -= min(15, Double(c.alcohol) * 5)
            factors.append("alcool")
        }
        return Score(value: Int(min(100, max(1, value)).rounded()), isComplete: true, factors: factors)
    }
}

extension DailyCheckIn {
    /// Today's entry, created on first use.
    @MainActor
    static func today(in context: ModelContext) -> DailyCheckIn {
        let day = DayKey.today
        let descriptor = FetchDescriptor<DailyCheckIn>(predicate: #Predicate { $0.day == day })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let entry = DailyCheckIn(day: day)
        context.insert(entry)
        return entry
    }
}

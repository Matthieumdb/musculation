import SwiftUI
import SwiftData

/// One piece of advice from the coach.
struct CoachInsight: Identifiable {
    enum Kind: Int {
        case action, warning, win, info

        var color: Color {
            switch self {
            case .action: .orange
            case .warning: .red
            case .win: .green
            case .info: .blue
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let symbol: String
    let title: String
    let message: String
    /// Exercise the advice is about, to show its demo or replace it.
    var exercise: Exercise? = nil
}

/// Rule-based analysis of the last workouts, run on the device.
enum Coach {
    /// Weekly hard sets per muscle that suit most people building muscle.
    static let weeklySetRange = 10...20

    struct Report {
        var headline: String
        var insights: [CoachInsight]
    }

    static func analyze(_ workouts: [Workout], now: Date = .now) -> Report {
        let finished = workouts
            .filter { $0.endedAt != nil && $0.setCount > 0 }
            .sorted { $0.startedAt > $1.startedAt }
        guard let last = finished.first else {
            return Report(
                headline: "Fais ta première séance : je l'analyserai pour te conseiller la suivante.",
                insights: []
            )
        }

        var insights: [CoachInsight] = []
        insights += frequency(finished, last: last, now: now)
        insights += exerciseTrends(finished, now: now)
        insights += weeklyVolume(finished, now: now)
        insights += balance(finished, now: now)
        insights += fatigue(finished, now: now)

        let sorted = insights.sorted { $0.kind.rawValue < $1.kind.rawValue }
        return Report(headline: headline(for: sorted, last: last, now: now), insights: sorted)
    }

    // MARK: - Rules

    private static func headline(for insights: [CoachInsight], last: Workout, now: Date) -> String {
        let wins = insights.filter { $0.kind == .win }.count
        let actions = insights.filter { $0.kind == .action }.count
        let warnings = insights.filter { $0.kind == .warning }.count
        let days = Calendar.current.dateComponents([.day], from: last.startedAt, to: now).day ?? 0
        let when = days == 0 ? "aujourd'hui" : days == 1 ? "hier" : "il y a \(days) jours"
        var parts = ["Dernière séance \(when)."]
        if wins > 0 { parts.append("\(wins) point\(wins > 1 ? "s" : "") fort\(wins > 1 ? "s" : "").") }
        if actions + warnings > 0 {
            parts.append("\(actions + warnings) conseil\(actions + warnings > 1 ? "s" : "") pour la suite.")
        }
        return parts.joined(separator: " ")
    }

    private static func frequency(_ workouts: [Workout], last: Workout, now: Date) -> [CoachInsight] {
        let days = Calendar.current.dateComponents([.day], from: last.startedAt, to: now).day ?? 0
        let lastFourWeeks = workouts.filter { now.timeIntervalSince($0.startedAt) < 28 * 86_400 }.count
        let perWeek = Double(lastFourWeeks) / 4
        var insights: [CoachInsight] = []
        if days >= 5 {
            insights.append(CoachInsight(
                kind: .warning,
                symbol: "calendar.badge.exclamationmark",
                title: "\(days) jours sans séance",
                message: "Reprends avec une séance un peu plus légère (une série de moins par exercice), puis retrouve ton rythme."
            ))
        }
        if lastFourWeeks >= 4 {
            insights.append(CoachInsight(
                kind: perWeek >= 3 ? .win : .info,
                symbol: "flame.fill",
                title: "\(perWeek.formatted(.number.precision(.fractionLength(0...1)))) séances par semaine",
                message: perWeek >= 3
                    ? "Belle régularité sur les 4 dernières semaines. C'est le premier moteur de progrès."
                    : "Sur les 4 dernières semaines. Viser 3 séances ou plus par semaine permet de travailler chaque muscle deux fois."
            ))
        }
        return insights
    }

    private struct Session {
        let date: Date
        let best: Double
        let topWeight: Double
        let entry: WorkoutExercise
    }

    private static func exerciseTrends(_ workouts: [Workout], now: Date) -> [CoachInsight] {
        let recent = workouts.filter { now.timeIntervalSince($0.startedAt) < 70 * 86_400 }
        var sessions: [PersistentIdentifier: (exercise: Exercise, sessions: [Session])] = [:]
        for workout in recent {
            for entry in workout.exercises {
                guard let exercise = entry.exercise, !entry.sets.isEmpty else { continue }
                let key = exercise.persistentModelID
                let session = Session(date: workout.startedAt, best: entry.bestOneRepMax, topWeight: entry.maxWeight, entry: entry)
                sessions[key, default: (exercise, [])].sessions.append(session)
            }
        }
        guard let lastDate = workouts.first?.startedAt else { return [] }

        var records: [CoachInsight] = []
        var progress: [CoachInsight] = []
        var stalls: [CoachInsight] = []
        var drops: [CoachInsight] = []

        for (exercise, list) in sessions.values {
            let ordered = list.sorted { $0.date > $1.date }
            guard let latest = ordered.first, latest.best > 0 else { continue }
            let previous = ordered.dropFirst()
            let previousBest = previous.map(\.best).max() ?? 0
            let isLastWorkout = Calendar.current.isDate(latest.date, inSameDayAs: lastDate)

            if isLastWorkout, previousBest > 0, latest.best > previousBest * 1.005 {
                records.append(CoachInsight(
                    kind: .win,
                    symbol: "trophy.fill",
                    title: "Record sur \(exercise.name)",
                    message: "1RM estimé \(latest.best.kgText) contre \(previousBest.kgText) avant. Continue sur cette lancée.",
                    exercise: exercise
                ))
                continue
            }

            if isLastWorkout, let increment = nextIncrement(for: latest.entry, exercise: exercise) {
                progress.append(CoachInsight(
                    kind: .action,
                    symbol: "arrow.up.circle.fill",
                    title: "Monte la charge sur \(exercise.name)",
                    message: "Tu as fait toutes tes répétitions cibles. La prochaine fois, essaie \((latest.topWeight + increment).kgText) (+\(increment.preciseKgText)).",
                    exercise: exercise
                ))
                continue
            }

            // Effort: the RPE the user logged, or the one expected from their recent best.
            if isLastWorkout {
                let rpes = latest.entry.sets.compactMap { set in
                    set.rpe ?? RPE.estimate(weight: set.weight, reps: set.reps, reference: previousBest > 0 ? previousBest : nil)
                }
                let logged = latest.entry.sets.contains { $0.rpe != nil }
                if rpes.count >= 2 {
                    let average = rpes.reduce(0, +) / Double(rpes.count)
                    let source = logged ? "noté" : "calculé"
                    if average <= 7, latest.topWeight > 0 {
                        let increment = exercise.progressionIncrement(from: latest.topWeight)
                        progress.append(CoachInsight(
                            kind: .action,
                            symbol: "gauge.with.dots.needle.33percent",
                            title: "\(exercise.name) était facile",
                            message: "RPE moyen \(source) \(RPE.label(average)) : il te restait 3 reps ou plus en réserve. Passe à \((latest.topWeight + increment).kgText) la prochaine fois.",
                            exercise: exercise
                        ))
                        continue
                    }
                    if average >= 9.5 {
                        drops.append(CoachInsight(
                            kind: .warning,
                            symbol: "gauge.with.dots.needle.100percent",
                            title: "\(exercise.name) à la limite",
                            message: "RPE moyen \(source) \(RPE.label(average)) : presque toutes tes séries étaient à l'échec. Garde la même charge et vise 1 à 2 reps en réserve pour mieux récupérer.",
                            exercise: exercise
                        ))
                        continue
                    }
                }
            }

            // Stalled: the last three sessions never beat the best done before them.
            if ordered.count >= 4 {
                let lastThree = ordered.prefix(3).map(\.best)
                let before = ordered.dropFirst(3).map(\.best).max() ?? 0
                if before > 0, (lastThree.max() ?? 0) <= before * 1.005 {
                    stalls.append(CoachInsight(
                        kind: .action,
                        symbol: "pause.circle.fill",
                        title: "\(exercise.name) stagne",
                        message: "Pas de progrès sur tes 3 dernières séances. Essaie d'ajouter une répétition par série avant de monter la charge, change de fourchette (par exemple 6–8 au lieu de 10–12) ou remplace-le par une variante.",
                        exercise: exercise
                    ))
                    continue
                }
            }

            if isLastWorkout, previousBest > 0, latest.best < previousBest * 0.92 {
                drops.append(CoachInsight(
                    kind: .warning,
                    symbol: "arrow.down.circle.fill",
                    title: "Baisse sur \(exercise.name)",
                    message: "1RM estimé \(latest.best.kgText), 8 % sous ton meilleur récent (\(previousBest.kgText)). Sommeil, alimentation ou fatigue : garde la même charge la prochaine fois.",
                    exercise: exercise
                ))
            }
        }

        return Array(records.prefix(3)) + Array(progress.prefix(4)) + Array(stalls.prefix(3)) + Array(drops.prefix(3))
    }

    /// Weight to add when every set reached the target reps of a template exercise.
    private static func nextIncrement(for entry: WorkoutExercise, exercise: Exercise) -> Double? {
        guard let target = entry.targetReps,
              WorkoutExercise.reachedTarget(entry.orderedSets, targetReps: target)
        else { return nil }
        let increment = exercise.progressionIncrement(from: entry.maxWeight)
        return increment > 0 && entry.maxWeight > 0 ? increment : nil
    }

    private static func setsPerGroup(_ workouts: [Workout], days: Double, now: Date) -> [MuscleGroup: Int] {
        var counts: [MuscleGroup: Int] = [:]
        for workout in workouts where now.timeIntervalSince(workout.startedAt) < days * 86_400 {
            for entry in workout.exercises {
                guard let group = entry.exercise?.muscleGroup else { continue }
                counts[group, default: 0] += entry.sets.count
            }
        }
        return counts
    }

    private static func weeklyVolume(_ workouts: [Workout], now: Date) -> [CoachInsight] {
        // Average of the last two weeks, to smooth a split over 8–10 days.
        let twoWeeks = setsPerGroup(workouts, days: 14, now: now)
        let trained = Set(setsPerGroup(workouts, days: 42, now: now).keys)
        let main: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .legs]
        var low: [String] = []
        var high: [String] = []
        for group in main where trained.contains(group) {
            let weekly = (twoWeeks[group] ?? 0) / 2
            if weekly < weeklySetRange.lowerBound {
                low.append("\(group.label) \(weekly)")
            } else if weekly > weeklySetRange.upperBound + 4 {
                high.append("\(group.label) \(weekly)")
            }
        }
        var insights: [CoachInsight] = []
        if !low.isEmpty {
            insights.append(CoachInsight(
                kind: .action,
                symbol: "chart.bar.fill",
                title: "Volume un peu juste",
                message: "Séries par semaine : \(low.joined(separator: ", ")). Pour la prise de muscle, vise 10 à 20 séries par muscle et par semaine : ajoute une série ou un exercice pour ces muscles."
            ))
        }
        if !high.isEmpty {
            insights.append(CoachInsight(
                kind: .warning,
                symbol: "chart.bar.xaxis",
                title: "Beaucoup de volume",
                message: "Séries par semaine : \(high.joined(separator: ", ")). Au-delà de 20 à 25, la récupération devient difficile : privilégie la qualité des séries."
            ))
        }
        let total = main.compactMap { trained.contains($0) ? (twoWeeks[$0] ?? 0) / 2 : nil }
        if low.isEmpty, high.isEmpty, !total.isEmpty {
            insights.append(CoachInsight(
                kind: .win,
                symbol: "checkmark.seal.fill",
                title: "Volume bien dosé",
                message: "Chaque muscle principal reçoit entre 10 et 24 séries par semaine."
            ))
        }
        return insights
    }

    private static func balance(_ workouts: [Workout], now: Date) -> [CoachInsight] {
        let counts = setsPerGroup(workouts, days: 14, now: now)
        let push = (counts[.chest] ?? 0) + (counts[.shoulders] ?? 0)
        let pull = counts[.back] ?? 0
        guard push + pull >= 12 else { return [] }
        if Double(push) > Double(pull) * 1.5 {
            return [CoachInsight(
                kind: .action,
                symbol: "scalemass.fill",
                title: "Plus de poussée que de tirage",
                message: "\(push) séries pecs et épaules contre \(pull) pour le dos sur 2 semaines. Ajoute du rowing ou du tirage pour protéger tes épaules et ta posture."
            )]
        }
        if Double(pull) > Double(push) * 1.8 {
            return [CoachInsight(
                kind: .info,
                symbol: "scalemass.fill",
                title: "Beaucoup de tirage",
                message: "\(pull) séries de dos contre \(push) pour pecs et épaules sur 2 semaines."
            )]
        }
        return []
    }

    private static func fatigue(_ workouts: [Workout], now: Date) -> [CoachInsight] {
        // Consecutive weeks with at least 3 workouts.
        let calendar = Calendar.current
        var streak = 0
        var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        while true {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            let count = workouts.filter { $0.startedAt >= previous && $0.startedAt < week }.count
            guard count >= 3 else { break }
            streak += 1
            week = previous
        }
        guard streak >= 7 else { return [] }
        return [CoachInsight(
            kind: .warning,
            symbol: "battery.25",
            title: "\(streak) semaines intenses d'affilée",
            message: "Prévois une semaine de décharge : mêmes exercices, moitié moins de séries, sans aller à l'échec. Tu reviendras plus fort."
        )]
    }
}

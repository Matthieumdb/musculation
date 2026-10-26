import Foundation
import UserNotifications

/// A week of training, eating and body data, for the Sunday recap.
struct WeeklyRecap {
    struct Record: Identifiable {
        var exercise: String
        var oneRepMax: Double
        var previous: Double
        var id: String { exercise }
    }

    struct MuscleSets: Identifiable {
        var group: MuscleGroup
        var sets: Int
        var id: MuscleGroup { group }
    }

    var week: DateInterval
    var workouts: Int
    var previousWorkouts: Int
    var duration: TimeInterval
    var volume: Double
    var previousVolume: Double
    var sets: Int
    var records: [Record]
    var muscles: [MuscleSets]
    /// Days with food logged, and their averages.
    var loggedDays: Int
    var averageKcal: Double?
    var averageProtein: Double?
    var targetKcal: Double
    var targetProtein: Double
    var weightStart: Double?
    var weightEnd: Double?
    var averageSleep: Double?
    var averageWater: Double?

    var isEmpty: Bool { workouts == 0 && loggedDays == 0 && weightEnd == nil && averageSleep == nil }

    static func week(containing date: Date) -> DateInterval {
        Calendar.current.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86_400)
    }

    static func make(
        week: DateInterval,
        workouts all: [Workout],
        logs: [String: [LogEntry]],
        targets: Macros,
        weights: [BodyWeightEntry],
        checkIns: [DailyCheckIn]
    ) -> WeeklyRecap {
        let finished = all.filter { $0.endedAt != nil }
        let inWeek = finished.filter { week.contains($0.startedAt) }
        let previousWeek = DateInterval(start: week.start.addingTimeInterval(-week.duration), duration: week.duration)
        let inPrevious = finished.filter { previousWeek.contains($0.startedAt) }

        // Sets per muscle, warm-ups left out
        var perGroup: [MuscleGroup: Int] = [:]
        var sets = 0
        for workout in inWeek {
            for entry in workout.exercises {
                let done = entry.sets.filter { $0.isCompleted && $0.kind != .warmup }.count
                sets += done
                if let group = entry.exercise?.muscleGroup, group != .cardio { perGroup[group, default: 0] += done }
            }
        }

        // Best estimated 1RM this week against everything before it
        var best: [String: Double] = [:]
        var before: [String: Double] = [:]
        for workout in finished where workout.startedAt < week.end {
            for entry in workout.exercises {
                guard let name = entry.exercise?.name else { continue }
                let value = entry.bestOneRepMax
                if week.contains(workout.startedAt) {
                    best[name] = max(best[name] ?? 0, value)
                } else if workout.startedAt < week.start {
                    before[name] = max(before[name] ?? 0, value)
                }
            }
        }
        let records = best.compactMap { name, value -> Record? in
            guard let previous = before[name], previous > 0, value > previous else { return nil }
            return Record(exercise: name, oneRepMax: value, previous: previous)
        }
        .sorted { $0.oneRepMax / $0.previous > $1.oneRepMax / $1.previous }

        // Food, only on days something was logged
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: week.start) }
            .filter { $0 <= .now }
            .map(DayKey.of)
        let eaten = days.compactMap { day -> Macros? in
            guard let entries = logs[day], !entries.isEmpty else { return nil }
            return entries.reduce(Macros.zero) { $0 + $1.macros }
        }

        let weekWeights = weights.filter { week.contains($0.date) }.sorted { $0.date < $1.date }
        let lastBefore = weights.filter { $0.date < week.start }.max { $0.date < $1.date }

        let weekCheckIns = checkIns.filter { days.contains($0.day) }
        let sleeps = weekCheckIns.compactMap(\.sleepHours)
        let water = weekCheckIns.map(\.water).filter { $0 > 0 }

        return WeeklyRecap(
            week: week,
            workouts: inWeek.count,
            previousWorkouts: inPrevious.count,
            duration: inWeek.reduce(0) { $0 + $1.duration },
            volume: inWeek.reduce(0) { $0 + $1.totalVolume },
            previousVolume: inPrevious.reduce(0) { $0 + $1.totalVolume },
            sets: sets,
            records: records,
            muscles: perGroup.map { MuscleSets(group: $0.key, sets: $0.value) }.sorted { $0.sets > $1.sets },
            loggedDays: eaten.count,
            averageKcal: eaten.isEmpty ? nil : eaten.reduce(0) { $0 + $1.kcal } / Double(eaten.count),
            averageProtein: eaten.isEmpty ? nil : eaten.reduce(0) { $0 + $1.p } / Double(eaten.count),
            targetKcal: targets.kcal,
            targetProtein: targets.p,
            weightStart: lastBefore?.weight ?? weekWeights.first?.weight,
            weightEnd: weekWeights.last?.weight,
            averageSleep: sleeps.isEmpty ? nil : sleeps.reduce(0, +) / Double(sleeps.count),
            averageWater: water.isEmpty ? nil : Double(water.reduce(0, +)) / Double(water.count)
        )
    }

    /// One sentence that sums the week up.
    var headline: String {
        if workouts == 0 { return loggedDays > 0 ? "Pas de séance cette semaine, mais tu as suivi ton alimentation." : "Une semaine calme." }
        if !records.isEmpty { return "\(records.count) record\(records.count > 1 ? "s" : "") battu\(records.count > 1 ? "s" : "") en \(workouts) séance\(workouts > 1 ? "s" : "")." }
        if previousVolume > 0, volume > previousVolume * 1.05 { return "Plus de volume que la semaine d'avant." }
        return "\(workouts) séance\(workouts > 1 ? "s" : "") au compteur."
    }
}

/// Sunday evening reminder that the recap is ready.
enum WeeklyRecapNotifier {
    static let enabledKey = "weeklyRecapNotification"
    private static let identifier = "weekly-recap"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Ton bilan de la semaine"
        content.body = "Séances, records, alimentation et poids : regarde comment s'est passée ta semaine."
        content.sound = .default

        var when = DateComponents()
        when.weekday = 1 // Sunday
        when.hour = 19
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}

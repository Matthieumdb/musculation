import Foundation

/// Lighter training asked by the recovery coach: one light day, or a whole deload week.
/// Template workouts then start with half the sets and no weight increase.
enum TrainingMode {
    static let lightDayKey = "coach.lightDay"
    static let deloadUntilKey = "coach.deloadUntil"

    static var isLightToday: Bool {
        UserDefaults.standard.string(forKey: lightDayKey) == DayKey.today
    }

    /// End of the current deload week, nil when none is running.
    static var deloadEnd: Date? {
        let end = UserDefaults.standard.double(forKey: deloadUntilKey)
        guard end > Date.now.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: end)
    }

    static var isReduced: Bool { isLightToday || deloadEnd != nil }
}

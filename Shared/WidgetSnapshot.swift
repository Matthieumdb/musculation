import Foundation

/// Figures shown by the home and lock screen widgets, written by the app into the shared App Group.
struct WidgetSnapshot: Codable, Hashable {
    var day: String
    var workoutsThisWeek: Int
    var weekStreak: Int
    var kcalLeft: Int
    var kcalTarget: Int
    var proteinLeft: Int
    var trainingBonus: Int?
    var proteinTarget: Int?
    var carbsLeft: Int?
    var carbsTarget: Int?
    var fatLeft: Int?
    var fatTarget: Int?
    /// Glasses of water (25 cl) on `waterDay`.
    var water: Int?
    var waterGoal: Int?
    var waterDay: String?

    static let appGroup = "group.com.matthieumdb.musculation"
    private static let key = "widget.snapshot"

    static var placeholder: WidgetSnapshot { WidgetSnapshot(
        day: "", workoutsThisWeek: 3, weekStreak: 4, kcalLeft: 820, kcalTarget: 2400, proteinLeft: 45, trainingBonus: 220,
        proteinTarget: 150, carbsLeft: 110, carbsTarget: 280, fatLeft: 25, fatTarget: 75, water: 5, waterGoal: 10, waterDay: todayKey
    ) }

    /// Nil when the App Group is unavailable (some sideloading tools do not keep it).
    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup), let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Calories are for one day only: on another day the widget shows the target again.
    var isToday: Bool { day == Self.todayKey }

    /// Glasses drunk today, 0 once the day has changed.
    var waterToday: Int { waterDay == Self.todayKey ? water ?? 0 : 0 }

    static var todayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}

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

    static let appGroup = "group.com.matthieumdb.musculation"
    private static let key = "widget.snapshot"

    static let placeholder = WidgetSnapshot(day: "", workoutsThisWeek: 3, weekStreak: 4, kcalLeft: 820, kcalTarget: 2400, proteinLeft: 45, trainingBonus: 220)

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
    var isToday: Bool {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return day == f.string(from: .now)
    }
}

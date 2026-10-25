import Foundation

enum AppSettings {
    static let restDurationKey = "restDuration"
    static let progressionPercentKey = "progressionPercent"
    static let barWeightKey = "barWeight"

    static let defaultRestDuration = 90
    static let defaultProgressionPercent = 2.5
    static let defaultBarWeight = 20.0

    static let restOptions = [60, 90, 120, 150, 180, 240]
    static let progressionOptions = [2.5, 5.0]
    static let barOptions = [20.0, 15.0, 10.0, 0.0]

    static var progressionPercent: Double {
        UserDefaults.standard.object(forKey: progressionPercentKey) as? Double ?? defaultProgressionPercent
    }

    /// "1 min 30"
    static func restLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60)"
    }
}

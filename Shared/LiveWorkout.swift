import Foundation

/// The running workout as the watch and the lock screen see it.
struct LiveWorkout: Codable, Hashable {
    struct Exercise: Codable, Hashable {
        var name: String
        var sets: [Set]
    }

    struct Set: Codable, Hashable {
        var weight: Double
        var reps: Int
        var done: Bool
    }

    struct Position: Hashable {
        var exercise: Int
        var set: Int
    }

    var title: String
    var startedAt: Date
    var restEnd: Date?
    var restTotal: Double
    var exercises: [Exercise]

    var doneSets: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// The first set not done yet, in exercise order.
    var current: Position? {
        for (e, exercise) in exercises.enumerated() {
            if let s = exercise.sets.firstIndex(where: { !$0.done }) { return Position(exercise: e, set: s) }
        }
        return nil
    }

    var isResting: Bool { (restEnd ?? .distantPast) > .now }
}

/// What the watch asks the iPhone to do.
enum WatchCommand: Codable, Hashable {
    case complete(exercise: Int, set: Int)
    case addRest
    case skipRest
}

/// Keys of the WatchConnectivity payloads.
enum WatchKeys {
    static let workout = "workout"
    static let command = "command"
}

extension Double {
    /// "82,5 kg", without the decimals when they are zero.
    var liveKgText: String {
        let text = self.formatted(.number.precision(.fractionLength(0...1)))
        return "\(text) kg"
    }
}

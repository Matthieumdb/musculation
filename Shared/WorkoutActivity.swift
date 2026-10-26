#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity of a running workout: lock screen and Dynamic Island.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var detail: String
        var done: Int
        var total: Int
        var restStart: Date?
        var restEnd: Date?
    }

    var title: String
    var startedAt: Date
}
#endif

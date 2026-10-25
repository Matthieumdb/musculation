import Foundation
import SwiftData

@Model
final class BodyWeightEntry {
    var date: Date
    var weight: Double

    init(date: Date = .now, weight: Double) {
        self.date = date
        self.weight = weight
    }
}

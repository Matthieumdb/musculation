import Foundation
import SwiftData

/// A body measurement: a circumference in cm or the body fat percentage.
@Model
final class BodyMeasurement {
    var date: Date
    var kindRaw: String
    var value: Double

    init(date: Date = .now, kind: MeasurementKind, value: Double) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.value = value
    }

    var kind: MeasurementKind { MeasurementKind(rawValue: kindRaw) ?? .waist }
}

enum MeasurementKind: String, CaseIterable, Identifiable, Codable {
    case bodyFat, waist, chest, shoulders, arm, forearm, thigh, calf, hips, neck

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bodyFat: "Masse grasse"
        case .waist: "Tour de taille"
        case .chest: "Poitrine"
        case .shoulders: "Épaules"
        case .arm: "Bras"
        case .forearm: "Avant-bras"
        case .thigh: "Cuisse"
        case .calf: "Mollet"
        case .hips: "Hanches"
        case .neck: "Cou"
        }
    }

    var unit: String { self == .bodyFat ? "%" : "cm" }

    var symbol: String {
        switch self {
        case .bodyFat: "percent"
        case .waist, .hips: "figure.arms.open"
        case .chest, .shoulders: "figure.strengthtraining.traditional"
        case .arm, .forearm: "dumbbell.fill"
        case .thigh, .calf: "figure.walk"
        case .neck: "person.fill"
        }
    }

    /// Smaller is better for the waist, hips and body fat; bigger for the rest.
    var lowerIsBetter: Bool { [.bodyFat, .waist, .hips].contains(self) }

    func text(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }
}

/// How the day feels, as in Bevel's journal: sleep, energy, soreness, stress and habits.
@Model
final class DailyCheckIn {
    /// "yyyy-MM-dd", one entry per day.
    var day: String
    var sleepHours: Double?
    /// 1 (bad) to 5 (great)
    var sleepQuality: Int?
    var energy: Int?
    /// 1 (none) to 5 (very sore)
    var soreness: Int?
    var stress: Int?
    /// Glasses of 25 cl
    var water: Int = 0
    var alcohol: Int = 0
    var caffeine: Int = 0
    var note: String = ""

    init(day: String) {
        self.day = day
    }

    var hasFeelings: Bool { sleepHours != nil || sleepQuality != nil || energy != nil || soreness != nil || stress != nil }
}

import Foundation
import HealthKit
import SwiftData

/// Writes workouts and body weight to Apple Health, and reads body weight back.
enum HealthSync {
    static let enabledKey = "healthSyncEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let store = HKHealthStore()
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)

    /// Asks for access. Returns false when Health is unavailable or the request failed.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType(), bodyMass, activeEnergy],
                read: [bodyMass]
            )
            return true
        } catch {
            return false
        }
    }

    /// Strength training burns about 5 kcal per kg of body weight per hour (MET ≈ 5).
    static func estimatedCalories(duration: TimeInterval, bodyWeight: Double) -> Double {
        5 * bodyWeight * duration / 3600
    }

    static func save(workoutFrom start: Date, to end: Date, title: String, bodyWeight: Double?) async {
        guard isEnabled, isAvailable, end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            let calories = estimatedCalories(duration: end.timeIntervalSince(start), bodyWeight: bodyWeight ?? 75)
            let sample = HKCumulativeQuantitySample(
                type: activeEnergy,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: start,
                end: end
            )
            try await builder.addSamples([sample])
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: title])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
        }
    }

    static func save(bodyWeight: Double, at date: Date) async {
        guard isEnabled, isAvailable, bodyWeight > 0 else { return }
        let sample = HKQuantitySample(
            type: bodyMass,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: bodyWeight),
            start: date,
            end: date
        )
        try? await store.save(sample)
    }

    /// Body weights recorded in Health over the last two years, newest first.
    static func readBodyWeights() async -> [(date: Date, weight: Double)] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .year, value: -2, to: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass, predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    /// Adds Health weigh-ins for days that have none in the app. Returns how many were added.
    @MainActor
    static func importBodyWeights(into context: ModelContext) async -> Int {
        let weights = await readBodyWeights()
        let rounded = weights.map { (date: $0.date, weight: ($0.weight * 100).rounded() / 100) }
        return HevyImport.importBodyWeights(rounded, in: context)
    }
}

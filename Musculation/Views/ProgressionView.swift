import SwiftUI
import SwiftData
import Charts

struct ProgressionView: View {
    @Query private var exercises: [Exercise]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }) private var workouts: [Workout]

    private var trainedExercises: [Exercise] {
        exercises
            .filter { !$0.history.isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var thisWeek: [Workout] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return workouts.filter { week.contains($0.startedAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Cette semaine") {
                    LabeledContent("Séances", value: "\(thisWeek.count)")
                    LabeledContent("Volume", value: thisWeek.reduce(0) { $0 + $1.totalVolume }.kgText)
                }

                Section("Par exercice") {
                    ForEach(trainedExercises) { exercise in
                        NavigationLink(value: exercise) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                let best = exercise.history.map(\.bestOneRepMax).max() ?? 0
                                Text("1RM estimé : \(best.kgText) · \(exercise.history.count) séances")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if trainedExercises.isEmpty {
                        Text("Termine une séance pour voir ta progression.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Progrès")
            .navigationDestination(for: Exercise.self) { ExerciseProgressView(exercise: $0) }
        }
    }
}

struct ExerciseProgressView: View {
    let exercise: Exercise
    @State private var metric: Metric = .oneRepMax

    enum Metric: String, CaseIterable, Identifiable {
        case oneRepMax = "1RM estimé"
        case maxWeight = "Charge max"
        case volume = "Volume"

        var id: Self { self }

        func value(for entry: WorkoutExercise) -> Double {
            switch self {
            case .oneRepMax: entry.bestOneRepMax
            case .maxWeight: entry.maxWeight
            case .volume: entry.volume
            }
        }
    }

    private struct Point: Identifiable {
        let id: PersistentIdentifier
        let date: Date
        let value: Double
    }

    var body: some View {
        let history = exercise.history
        let points = history.reversed().compactMap { entry -> Point? in
            guard let date = entry.workout?.startedAt else { return nil }
            return Point(id: entry.persistentModelID, date: date, value: metric.value(for: entry))
        }
        let bestSet = history.compactMap(\.bestSet).max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }

        List {
            Section {
                Picker("Mesure", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
                .padding(.vertical, 8)
            }

            Section("Records") {
                LabeledContent("1RM estimé", value: (history.map(\.bestOneRepMax).max() ?? 0).kgText)
                LabeledContent("Charge max", value: (history.map(\.maxWeight).max() ?? 0).kgText)
                if let bestSet {
                    LabeledContent("Meilleure série", value: "\(bestSet.weight.kgText) × \(bestSet.reps)")
                }
                LabeledContent("Séances", value: "\(history.count)")
            }

            Section("Historique") {
                ForEach(history) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.workout?.startedAt.formatted(date: .abbreviated, time: .omitted) ?? "")
                            .font(.subheadline)
                        Text(entry.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

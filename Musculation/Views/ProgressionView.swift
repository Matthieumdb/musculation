import SwiftUI
import SwiftData
import Charts

struct ProgressionView: View {
    @Query private var exercises: [Exercise]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }) private var workouts: [Workout]
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var bodyWeights: [BodyWeightEntry]

    private struct WeekCount: Identifiable {
        let start: Date
        let count: Int
        var id: Date { start }
    }

    private struct MuscleCount: Identifiable {
        let group: MuscleGroup
        let sets: Int
        var id: MuscleGroup { group }
    }

    /// Workouts per week over the last 12 weeks, oldest first.
    private var weeklyCounts: [WeekCount] {
        let calendar = Calendar.current
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<12).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let count = workouts.filter { $0.startedAt >= start && $0.startedAt < end }.count
            return WeekCount(start: start, count: count)
        }
    }

    /// Sets per muscle group over the last 7 days.
    private var setsPerMuscle: [MuscleCount] {
        let since = Date.now.addingTimeInterval(-7 * 24 * 3600)
        var counts: [MuscleGroup: Int] = [:]
        for workout in workouts where workout.startedAt >= since {
            for entry in workout.exercises {
                guard let group = entry.exercise?.muscleGroup else { continue }
                counts[group, default: 0] += entry.sets.count
            }
        }
        return MuscleGroup.allCases.compactMap { group in
            counts[group].map { MuscleCount(group: group, sets: $0) }
        }
    }

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
                Section {
                    HStack(spacing: 10) {
                        StatTile(value: "\(thisWeek.count)", label: "séances cette semaine", symbol: "calendar", tint: .orange)
                        StatTile(
                            value: thisWeek.reduce(0) { $0 + $1.totalVolume }.kgText,
                            label: "soulevés cette semaine",
                            symbol: "scalemass.fill",
                            tint: .green
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Séances par semaine") {
                    Chart(weeklyCounts) { week in
                        BarMark(
                            x: .value("Semaine", week.start, unit: .weekOfYear),
                            y: .value("Séances", week.count)
                        )
                        .foregroundStyle(Theme.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    }
                    .frame(height: 150)
                    .padding(.vertical, 8)
                }

                Section {
                    if setsPerMuscle.isEmpty {
                        Text("Aucune série ces 7 derniers jours.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(setsPerMuscle) { item in
                        LabeledContent(item.group.label, value: "\(item.sets) séries")
                    }
                } header: {
                    Text("Séries par muscle (7 jours)")
                } footer: {
                    Text("Repère courant pour progresser : 10 à 20 séries par muscle et par semaine.")
                }

                Section("Poids de corps") {
                    NavigationLink {
                        BodyWeightView()
                    } label: {
                        if let latest = bodyWeights.first {
                            LabeledContent(
                                latest.weight.kgText,
                                value: latest.date.formatted(date: .abbreviated, time: .omitted)
                            )
                        } else {
                            Text("Ajouter une pesée")
                        }
                    }
                }

                Section("Par exercice") {
                    ForEach(trainedExercises) { exercise in
                        NavigationLink(value: exercise) {
                            HStack(spacing: 12) {
                                MuscleIcon(group: exercise.muscleGroup, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                    let best = exercise.history.map(\.bestOneRepMax).max() ?? 0
                                    Text("1RM estimé : \(best.kgText) · \(exercise.history.count) séances")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .foregroundStyle(Theme.gradient)
                    PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                        .foregroundStyle(Color.accentColor)
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

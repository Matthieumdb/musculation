import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            List {
                ForEach(workouts) { workout in
                    NavigationLink(value: workout) {
                        WorkoutRow(workout: workout)
                    }
                }
                .onDelete { offsets in
                    offsets.map { workouts[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            }
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "Aucune séance",
                        systemImage: "dumbbell",
                        description: Text("Tes séances terminées apparaîtront ici.")
                    )
                }
            }
            .navigationTitle("Historique")
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.title).font(.headline)
            Text(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(workout.exercises.count) exercices · \(workout.setCount) séries · \(workout.totalVolume.kgText) · \(durationText(workout.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct WorkoutDetailView: View {
    @Bindable var workout: Workout

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: workout.startedAt.formatted(date: .long, time: .shortened))
                LabeledContent("Durée", value: durationText(workout.duration))
                LabeledContent("Séries", value: "\(workout.setCount)")
                LabeledContent("Volume total", value: workout.totalVolume.kgText)
            }

            ForEach(workout.orderedExercises) { entry in
                Section(entry.exercise?.name ?? "Exercice supprimé") {
                    ForEach(Array(entry.orderedSets.enumerated()), id: \.element.id) { pair in
                        HStack {
                            Text("Série \(pair.offset + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(pair.element.weight.kgText) × \(pair.element.reps)")
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Notes") {
                TextField("Ressenti, douleurs, sommeil…", text: $workout.notes, axis: .vertical)
                    .lineLimit(2...8)
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

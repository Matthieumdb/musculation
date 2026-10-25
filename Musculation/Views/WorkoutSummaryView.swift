import SwiftUI

/// Snapshot of a workout taken just before it is finished, so the summary
/// never reads sets that get pruned afterwards.
struct WorkoutSummary: Identifiable {
    let id = UUID()
    let title: String
    let duration: TimeInterval
    let exerciseCount: Int
    let setCount: Int
    let volume: Double
    let records: [String]

    init(workout: Workout) {
        let entries = workout.orderedExercises
        let completed = entries.flatMap { $0.sets.filter(\.isCompleted) }
        title = workout.title
        duration = Date.now.timeIntervalSince(workout.startedAt)
        exerciseCount = entries.filter { $0.sets.contains(where: \.isCompleted) }.count
        setCount = completed.count
        volume = completed.reduce(0) { $0 + $1.volume }
        records = entries.compactMap { entry in
            guard let name = entry.exercise?.name,
                  let previousBest = entry.previousBestOneRepMax,
                  let best = entry.sets.filter(\.isCompleted).max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }),
                  best.estimatedOneRepMax > previousBest
            else { return nil }
            return "\(name) : \(best.weight.kgText) × \(best.reps)"
        }
    }
}

struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let summary: WorkoutSummary

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: summary.records.isEmpty ? "checkmark.seal.fill" : "trophy.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(summary.records.isEmpty ? Color.green : Color.yellow)
                        Text("Bien joué !").font(.title.bold())
                        Text(summary.title).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }

                Section {
                    LabeledContent("Durée", value: durationText(summary.duration))
                    LabeledContent("Exercices", value: "\(summary.exerciseCount)")
                    LabeledContent("Séries", value: "\(summary.setCount)")
                    LabeledContent("Volume", value: summary.volume.kgText)
                }

                if !summary.records.isEmpty {
                    Section("Nouveaux records") {
                        ForEach(summary.records, id: \.self) { record in
                            Label(record, systemImage: "trophy.fill")
                        }
                    }
                }
            }
            .navigationTitle("Séance terminée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

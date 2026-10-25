import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]

    private struct MonthSection: Identifiable {
        let month: Date
        let workouts: [Workout]
        var id: Date { month }
    }

    private var sections: [MonthSection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: workouts) {
            calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt
        }
        return grouped
            .map { MonthSection(month: $0.key, workouts: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.workouts) { workout in
                            NavigationLink(value: workout) {
                                WorkoutRow(workout: workout)
                            }
                        }
                        .onDelete { offsets in
                            withAnimation {
                                offsets.map { section.workouts[$0] }.forEach { context.delete($0) }
                                try? context.save()
                            }
                        }
                    } header: {
                        HStack {
                            Text(section.month.formatted(.dateTime.month(.wide).year()).capitalized)
                            Spacer()
                            Text("\(section.workouts.count) séance\(section.workouts.count > 1 ? "s" : "")")
                        }
                    }
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
        HStack(spacing: 12) {
            MuscleIcon(group: workout.mainMuscleGroup ?? .fullBody, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title).font(.headline)
                Text(workout.startedAt.formatted(.dateTime.weekday(.wide).day().hour().minute()).capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(durationText(workout.duration), systemImage: "clock")
                    Label("\(workout.setCount)", systemImage: "square.stack.3d.up")
                    Label(workout.totalVolume.kgText, systemImage: "scalemass")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }
        }
        .padding(.vertical, 2)
    }
}

/// Icon and title close together, for dense metadata rows.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var workout: Workout
    @State private var didCreateTemplate = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(workout.startedAt.formatted(date: .complete, time: .shortened).capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        StatTile(value: durationText(workout.duration), label: "durée", symbol: "clock.fill", tint: .orange)
                        StatTile(value: "\(workout.setCount)", label: "séries", symbol: "square.stack.3d.up.fill", tint: .blue)
                        StatTile(value: workout.totalVolume.kgText, label: "volume", symbol: "scalemass.fill", tint: .green)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            ForEach(workout.orderedExercises) { entry in
                Section {
                    ForEach(Array(entry.orderedSets.enumerated()), id: \.element.id) { pair in
                        HStack {
                            Text("Série \(pair.offset + 1)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(pair.element.weight.kgText) × \(pair.element.reps)")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        if let group = entry.exercise?.muscleGroup {
                            MuscleIcon(group: group, size: 24)
                        }
                        Text(entry.exercise?.name ?? "Exercice supprimé")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .textCase(nil)
                }
            }

            Section("Notes") {
                TextField("Ressenti, douleurs, sommeil…", text: $workout.notes, axis: .vertical)
                    .lineLimit(2...8)
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Enregistrer comme modèle", systemImage: "square.on.square") { createTemplate() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Modèle créé", isPresented: $didCreateTemplate) {
            Button("OK") {}
        } message: {
            Text("Retrouve « \(workout.title) » dans l'onglet Séance.")
        }
    }

    private func createTemplate() {
        let template = WorkoutTemplate(name: workout.title)
        context.insert(template)
        for entry in workout.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let item = template.addItem(exercise, in: context)
            item.targetSets = max(entry.sets.count, 1)
            item.targetReps = entry.targetReps ?? entry.orderedSets.first?.reps ?? 10
        }
        try? context.save()
        didCreateTemplate = true
    }
}

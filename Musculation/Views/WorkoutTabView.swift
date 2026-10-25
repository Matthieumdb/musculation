import SwiftUI
import SwiftData

struct WorkoutTabView: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }, sort: \Workout.startedAt, order: .reverse)
    private var activeWorkouts: [Workout]
    @State private var summary: WorkoutSummary?

    var body: some View {
        NavigationStack {
            if let workout = activeWorkouts.first {
                ActiveWorkoutView(workout: workout) { summary = $0 }
            } else {
                StartWorkoutView()
            }
        }
        .sheet(item: $summary) { WorkoutSummaryView(summary: $0) }
    }
}

struct StartWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @State private var editingTemplate: WorkoutTemplate?
    @State private var newTemplate: WorkoutTemplate?

    var body: some View {
        List {
            Section {
                Button {
                    context.insert(Workout(title: "Séance du \(Date.now.formatted(.dateTime.day().month(.wide)))"))
                    try? context.save()
                } label: {
                    Label("Démarrer une séance libre", systemImage: "play.fill")
                        .font(.headline)
                }
            }

            Section("Modèles") {
                if templates.isEmpty {
                    Text("Crée un modèle (Push, Pull, Legs…) pour démarrer une séance en un geste.")
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.headline)
                            if !template.summary.isEmpty {
                                Text(template.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button("Démarrer") { template.startWorkout(in: context) }
                            .buttonStyle(.borderedProminent)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingTemplate = template }
                }
                .onDelete { offsets in
                    offsets.map { templates[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }

                Button {
                    let template = WorkoutTemplate(name: "")
                    context.insert(template)
                    newTemplate = template
                } label: {
                    Label("Nouveau modèle", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Séance")
        .sheet(item: $editingTemplate) { TemplateEditView(template: $0, isNew: false) }
        .sheet(item: $newTemplate) { TemplateEditView(template: $0, isNew: true) }
    }
}

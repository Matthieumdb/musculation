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
        .animation(.snappy, value: activeWorkouts.isEmpty)
        .sheet(item: $summary) { WorkoutSummaryView(summary: $0) }
    }
}

struct StartWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.createdAt) private var templates: [WorkoutTemplate]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finishedWorkouts: [Workout]

    @State private var editingTemplate: WorkoutTemplate?
    @State private var newTemplate: WorkoutTemplate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                stats

                Button {
                    context.insert(Workout(title: "Séance du \(Date.now.formatted(.dateTime.day().month(.wide)))"))
                    try? context.save()
                } label: {
                    Label("Démarrer une séance libre", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                templatesSection

                if let last = finishedWorkouts.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Dernière séance").font(.title2.bold())
                        LastWorkoutCard(workout: last)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingTemplate) { TemplateEditView(template: $0, isNew: false) }
        .sheet(item: $newTemplate) { TemplateEditView(template: $0, isNew: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(greeting) 💪")
                .font(.largeTitle.bold())
        }
        .padding(.top, 8)
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatTile(value: "\(workoutsThisWeek)", label: "cette semaine", symbol: "calendar", tint: .orange)
            StatTile(
                value: "\(weekStreak)",
                label: weekStreak > 1 ? "semaines d'affilée" : "semaine d'affilée",
                symbol: "flame.fill",
                tint: .red
            )
            StatTile(value: "\(finishedWorkouts.count)", label: "séances au total", symbol: "trophy.fill", tint: .yellow)
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mes modèles").font(.title2.bold())
                Spacer()
                Button {
                    let template = WorkoutTemplate(name: "")
                    context.insert(template)
                    newTemplate = template
                } label: {
                    Label("Nouveau", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if templates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title)
                        .foregroundStyle(Theme.gradient)
                    Text("Crée ton premier modèle")
                        .font(.headline)
                    Text("Push, Pull, Legs… Démarre ensuite une séance en un geste, avec les charges de la dernière fois.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .card()
            }

            ForEach(templates) { template in
                TemplateCard(
                    template: template,
                    onStart: { template.startWorkout(in: context) },
                    onEdit: { editingTemplate = template }
                )
                .contextMenu {
                    Button("Modifier", systemImage: "pencil") { editingTemplate = template }
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        withAnimation {
                            context.delete(template)
                            try? context.save()
                        }
                    }
                }
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Bonjour"
        case 12..<18: "Bon après-midi"
        default: "Bonsoir"
        }
    }

    private var workoutsThisWeek: Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return finishedWorkouts.filter { week.contains($0.startedAt) }.count
    }

    /// Consecutive weeks with at least one workout, counting this week only once it has one.
    private var weekStreak: Int {
        let calendar = Calendar.current
        let trainedWeeks = Set(finishedWorkouts.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        if !trainedWeeks.contains(week) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { return 0 }
            week = previous
        }
        var streak = 0
        while trainedWeeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return streak
    }
}

private struct TemplateCard: View {
    let template: WorkoutTemplate
    var onStart: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.headline)
                    Text("\(template.items.count) exercice\(template.items.count > 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.gradient, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Démarrer \(template.name)")
            }

            if !template.muscleGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(template.muscleGroups) { MuscleChip(group: $0) }
                    }
                }
            }

            if !template.summary.isEmpty {
                Text(template.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

private struct LastWorkoutCard: View {
    let workout: Workout

    var body: some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack(spacing: 14) {
                MuscleIcon(group: workout.mainMuscleGroup ?? .fullBody, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(workout.startedAt.formatted(.relative(presentation: .named)).capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label(durationText(workout.duration), systemImage: "clock")
                        Label(workout.totalVolume.kgText, systemImage: "scalemass")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(PressableButtonStyle())
    }
}

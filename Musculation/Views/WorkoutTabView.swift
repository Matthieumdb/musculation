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

    @AppStorage(TrainingProgram.startDateKey) private var programStart: Double = 0
    @State private var editingTemplate: WorkoutTemplate?
    @State private var newTemplate: WorkoutTemplate?
    @State private var isShowingProgram = false
    @State private var isShowingCoach = false

    private var programTemplates: [WorkoutTemplate] {
        templates
            .filter { $0.programName != nil }
            .sorted { ($0.programOrder ?? 0) < ($1.programOrder ?? 0) }
    }

    private var customTemplates: [WorkoutTemplate] {
        templates.filter { $0.programName == nil }
    }

    /// The program session after the last one done, or the first one.
    private var nextProgramTemplate: WorkoutTemplate? {
        let sessions = programTemplates
        guard !sessions.isEmpty else { return nil }
        for workout in finishedWorkouts {
            if let index = sessions.firstIndex(where: { $0.name == workout.title }) {
                return sessions[(index + 1) % sessions.count]
            }
        }
        return sessions.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                stats

                if !finishedWorkouts.isEmpty {
                    CoachCard(report: Coach.analyze(Array(finishedWorkouts.prefix(120)))) {
                        isShowingCoach = true
                    }
                }

                Button {
                    context.insert(Workout(title: "Séance du \(Date.now.formatted(.dateTime.day().month(.wide)))"))
                    try? context.save()
                } label: {
                    Label("Démarrer une séance libre", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                programSection

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
        .background { AppBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingTemplate) { TemplateEditView(template: $0, isNew: false) }
        .sheet(item: $newTemplate) { TemplateEditView(template: $0, isNew: true) }
        .sheet(isPresented: $isShowingCoach) { CoachView() }
        .sheet(isPresented: $isShowingProgram) {
            if let programName = programTemplates.first?.programName {
                ProgramDetailView(programName: programName)
            }
        }
    }

    @ViewBuilder
    private var programSection: some View {
        if let next = nextProgramTemplate {
            let phase = TrainingProgram.phase(startedAt: Date(timeIntervalSince1970: programStart))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mon programme").font(.title2.bold())
                    Spacer()
                    Button("Détails") { isShowingProgram = true }
                        .font(.subheadline.weight(.semibold))
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("Semaine \(phase.week)/\(TrainingProgram.cycleWeeks)")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.25), in: Capsule())
                        Text(phase.title)
                    }
                    .font(.caption.bold())

                    Text(phase.detail)
                        .font(.subheadline)
                        .opacity(0.9)

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prochaine séance")
                                .font(.caption)
                                .opacity(0.85)
                            Text(next.name)
                                .font(.largeTitle.bold())
                            Text("\(next.items.count) exercices\(phase.isDeload ? " · séries réduites" : "")")
                                .font(.caption)
                                .opacity(0.85)
                        }
                        Spacer()
                        Button {
                            next.startWorkout(in: context, deload: phase.isDeload)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundStyle(Color(red: 0.84, green: 0.13, blue: 0.24))
                                .frame(width: 64, height: 64)
                                .background(.white, in: Circle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Démarrer \(next.name)")
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(programTemplates) { template in
                                Button {
                                    template.startWorkout(in: context, deload: phase.isDeload)
                                } label: {
                                    Text(template.name)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            .white.opacity(template.persistentModelID == next.persistentModelID ? 0.4 : 0.18),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(PressableButtonStyle())
                                .contextMenu {
                                    Button("Modifier les exercices", systemImage: "pencil") {
                                        editingTemplate = template
                                    }
                                }
                            }
                        }
                    }
                    Text("Appui long sur une séance pour remplacer ses exercices.")
                        .font(.caption2)
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(red: 0.84, green: 0.13, blue: 0.24).opacity(0.25), radius: 12, y: 6)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Programmes").font(.title2.bold())
                ForEach(TrainingProgram.all, id: \.name) { program in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Theme.gradient)
                            Text(program.name).font(.headline)
                        }
                        Text(program.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(program.sessions) { session in
                                Text(session.name)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.field, in: Capsule())
                            }
                        }
                        Button {
                            withAnimation(.snappy) {
                                program.install(in: context)
                                programStart = Date.now.timeIntervalSince1970
                            }
                        } label: {
                            Label("Suivre ce programme", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 4)
                    }
                    .card()
                }
            }
        }
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

            if customTemplates.isEmpty {
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

            ForEach(customTemplates) { template in
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

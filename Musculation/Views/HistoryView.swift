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
                if !workouts.isEmpty {
                    Section {
                        WorkoutCalendar(days: Set(workouts.map { Calendar.current.startOfDay(for: $0.startedAt) }))
                    }
                }
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
    @State private var didRepeat = false
    @State private var shareImage: Image?
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }) private var activeWorkouts: [Workout]

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
                            Text(pair.element.kind == .normal ? "Série \(pair.offset + 1)" : pair.element.kind.label)
                                .foregroundStyle(pair.element.kind == .warmup ? Color.orange : Color.secondary)
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

            Section("Horaires") {
                DatePicker("Début", selection: $workout.startedAt)
                DatePicker("Fin", selection: Binding(
                    get: { workout.endedAt ?? workout.startedAt },
                    set: { workout.endedAt = max($0, workout.startedAt) }
                ), in: workout.startedAt...)
            }
        }
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Refaire cette séance", systemImage: "arrow.clockwise") { repeatWorkout() }
                    Button("Enregistrer comme modèle", systemImage: "square.on.square") { createTemplate() }
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview(workout.title, image: shareImage)) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { shareImage = WorkoutShareCard.render(workout) }
        .alert("Séance démarrée", isPresented: $didRepeat) {
            Button("OK") {}
        } message: {
            Text("Elle t'attend dans l'onglet Séance, avec les charges de cette fois-ci.")
        }
        .alert("Modèle créé", isPresented: $didCreateTemplate) {
            Button("OK") {}
        } message: {
            Text("Retrouve « \(workout.title) » dans l'onglet Séance.")
        }
    }

    /// Starts a new workout with the same exercises and number of sets.
    private func repeatWorkout() {
        guard activeWorkouts.isEmpty else { return }
        let copy = Workout(title: workout.title)
        context.insert(copy)
        for entry in workout.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let added = copy.addExercise(
                exercise,
                targetSets: max(entry.sets.filter { $0.kind != .warmup }.count, 1),
                targetReps: entry.targetReps,
                minReps: entry.minReps,
                restSeconds: entry.restSeconds,
                note: entry.note,
                in: context
            )
            added.supersetGroup = entry.supersetGroup
        }
        try? context.save()
        didRepeat = true
    }

    private func createTemplate() {
        let template = WorkoutTemplate(name: workout.title)
        context.insert(template)
        for entry in workout.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let item = template.addItem(exercise, in: context)
            item.targetSets = max(entry.sets.count, 1)
            item.targetReps = entry.targetReps ?? entry.orderedSets.first?.reps ?? 10
            item.minReps = entry.minReps
            item.restSeconds = entry.restSeconds
            item.notes = entry.note
        }
        try? context.save()
        didCreateTemplate = true
    }
}

/// Month grid with a dot on each training day, as in Hevy's profile.
private struct WorkoutCalendar: View {
    let days: Set<Date>
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    var body: some View {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<31
        let firstWeekday = calendar.component(.weekday, from: month)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: leading) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        let count = cells.compactMap { $0 }.filter { days.contains($0) }.count
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])

        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()).capitalized).font(.headline)
                Text("· \(count) séance\(count > 1 ? "s" : "")").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Mois précédent")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Mois suivant")
                    .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
            }
            .buttonStyle(.borderless)
            .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let trained = days.contains(day)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.footnote.weight(trained ? .bold : .regular))
                            .monospacedDigit()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(trained ? Color.white : (calendar.isDateInToday(day) ? Color.accentColor : Color.primary))
                            .background {
                                if trained { Circle().fill(Color.accentColor) }
                                else if calendar.isDateInToday(day) { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
                            }
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func shift(_ months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: month) {
            withAnimation(.appSpring) { month = next }
        }
    }
}

/// Image to share a workout: title, figures and the best set of each exercise.
struct WorkoutShareCard: View {
    let workout: Workout

    @MainActor
    static func render(_ workout: Workout) -> Image? {
        let renderer = ImageRenderer(content: WorkoutShareCard(workout: workout).environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Musculation", systemImage: "dumbbell.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(workout.title).font(.largeTitle.bold())
            HStack(spacing: 24) {
                figure(durationText(workout.duration), "durée")
                figure("\(workout.setCount)", "séries")
                figure(workout.totalVolume.kgText, "volume")
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(workout.orderedExercises.prefix(8)) { entry in
                    HStack {
                        Text(entry.exercise?.name ?? "Exercice").lineLimit(1)
                        Spacer()
                        if let best = entry.bestSet {
                            Text("\(best.weight.kgText) × \(best.reps)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.white)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(22))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

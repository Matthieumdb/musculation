import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var workout: Workout
    var onFinish: (WorkoutSummary) -> Void

    @AppStorage(AppSettings.restDurationKey) private var restDuration = AppSettings.defaultRestDuration
    @State private var restEndDate: Date?
    @State private var restTotal: TimeInterval = 90
    @State private var isPickingExercise = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false
    @State private var plateTarget: PlateTarget?

    var body: some View {
        let entries = workout.orderedExercises
        let allSets = entries.flatMap(\.sets)
        let doneSets = allSets.filter(\.isCompleted)

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Nom de la séance", text: $workout.title)
                        .font(.title2.bold())

                    HStack(spacing: 0) {
                        TimelineView(.periodic(from: workout.startedAt, by: 1)) { timeline in
                            metric(
                                Duration.seconds(max(0, timeline.date.timeIntervalSince(workout.startedAt)))
                                    .formatted(.time(pattern: .hourMinuteSecond)),
                                label: "Durée"
                            )
                        }
                        metric("\(doneSets.count)/\(allSets.count)", label: "Séries")
                        metric(doneSets.reduce(0) { $0 + $1.volume }.kgText, label: "Volume")
                    }

                    ProgressView(value: Double(doneSets.count), total: Double(max(allSets.count, 1)))
                        .tint(Color.accentColor)
                        .animation(.snappy, value: doneSets.count)
                }
                .padding(.vertical, 6)
            }

            ForEach(entries) { entry in
                WorkoutExerciseSection(
                    entry: entry,
                    canMoveUp: entry.persistentModelID != entries.first?.persistentModelID,
                    canMoveDown: entry.persistentModelID != entries.last?.persistentModelID,
                    onMove: { offset in withAnimation(.snappy) { workout.move(entry, by: offset) } },
                    onSetCompleted: { startRest(seconds: entry.restSeconds) },
                    onShowPlates: { plateTarget = PlateTarget(weight: $0) }
                )
            }

            Section {
                Button {
                    isPickingExercise = true
                } label: {
                    Label(entries.isEmpty ? "Ajouter ton premier exercice" : "Ajouter un exercice", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if let restEndDate {
                RestTimerBar(
                    endDate: restEndDate,
                    total: restTotal,
                    onAddTime: {
                        restTotal += 30
                        withAnimation(.snappy) { self.restEndDate = max(restEndDate, .now).addingTimeInterval(30) }
                    },
                    onDismiss: { withAnimation(.snappy) { self.restEndDate = nil } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: restEndDate) { _, endDate in
            if let endDate {
                RestNotifier.schedule(at: endDate)
            } else {
                RestNotifier.cancel()
            }
        }
        .navigationTitle("Séance en cours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Temps de repos", selection: $restDuration) {
                        ForEach(AppSettings.restOptions, id: \.self) { seconds in
                            Text("Repos : \(AppSettings.restLabel(seconds))").tag(seconds)
                        }
                    }
                    Button("Calculateur de disques", systemImage: "circle.grid.2x1") {
                        plateTarget = PlateTarget(weight: 60)
                    }
                    Button("Abandonner la séance", systemImage: "trash", role: .destructive) {
                        isConfirmingDiscard = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Terminer") { isConfirmingFinish = true }
                    .bold()
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { hideKeyboard() }
            }
        }
        .sheet(isPresented: $isPickingExercise) {
            ExercisePickerView { exercise in
                withAnimation(.snappy) {
                    _ = workout.addExercise(exercise, in: context)
                }
            }
        }
        .sheet(item: $plateTarget) { target in
            PlateCalculatorView(target: target.weight)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Terminer la séance ?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button("Terminer") { finish() }
        } message: {
            Text("Seules les séries cochées seront enregistrées.")
        }
        .confirmationDialog("Abandonner la séance ?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) {
                restEndDate = nil
                RestNotifier.cancel()
                workout.discard(in: context)
            }
        } message: {
            Text("Toutes les données de cette séance seront supprimées.")
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startRest(seconds: Int?) {
        RestNotifier.requestAuthorization()
        restTotal = TimeInterval(seconds ?? restDuration)
        withAnimation(.snappy) {
            restEndDate = .now.addingTimeInterval(restTotal)
        }
    }

    private func finish() {
        let summary = WorkoutSummary(workout: workout)
        restEndDate = nil
        RestNotifier.cancel()
        workout.finish(in: context)
        if summary.setCount > 0 {
            onFinish(summary)
        }
    }
}

struct PlateTarget: Identifiable {
    let id = UUID()
    let weight: Double
}

/// Column widths shared by the set header and the set rows.
private enum SetColumns {
    static let number: CGFloat = 30
    static let weight: CGFloat = 72
    static let reps: CGFloat = 54
    static let rpe: CGFloat = 38
    static let check: CGFloat = 36
}

struct WorkoutExerciseSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var entry: WorkoutExercise
    var canMoveUp: Bool
    var canMoveDown: Bool
    var onMove: (Int) -> Void
    var onSetCompleted: () -> Void
    var onShowPlates: (Double) -> Void

    @State private var demoEntry: LibraryExercise?
    @State private var isReplacing = false
    @State private var pendingSwap: PendingSwap?

    var body: some View {
        let previousBest = entry.previousBestOneRepMax
        let previousSets = entry.exercise?.history.first?.orderedSets ?? []

        Section {
            HStack(spacing: 8) {
                Text("Série").frame(width: SetColumns.number, alignment: .leading)
                Text("Objectif").frame(maxWidth: .infinity, alignment: .leading)
                Text("kg").frame(width: SetColumns.weight)
                Text("Reps").frame(width: SetColumns.reps)
                Text("RPE").frame(width: SetColumns.rpe)
                Image(systemName: "checkmark").frame(width: SetColumns.check)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)

            ForEach(Array(entry.orderedSets.enumerated()), id: \.element.id) { pair in
                let set = pair.element
                SetRow(
                    number: pair.offset + 1,
                    set: set,
                    previous: pair.offset < previousSets.count ? previousSets[pair.offset] : nil,
                    isRecord: set.isCompleted && previousBest.map { set.estimatedOneRepMax > $0 } == true,
                    referenceOneRepMax: previousBest,
                    onCompleted: onSetCompleted
                )
                .listRowBackground(set.isCompleted ? Color.green.opacity(0.14) : nil)
                .contextMenu {
                    Button("Calculer les disques", systemImage: "circle.grid.2x1") {
                        onShowPlates(set.weight)
                    }
                }
            }
            .onDelete { offsets in
                let sets = entry.orderedSets
                withAnimation(.snappy) {
                    offsets.map { sets[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            }

            Button {
                let last = entry.orderedSets.last
                withAnimation(.snappy) {
                    _ = entry.addSet(reps: last?.reps ?? 10, weight: last?.weight ?? 0, in: context)
                }
            } label: {
                Label("Ajouter une série", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
        } header: {
            HStack(spacing: 10) {
                if let exercise = entry.exercise {
                    if let demo = exercise.libraryEntry {
                        Button {
                            demoEntry = demo
                        } label: {
                            ExerciseThumbnail(entry: demo, size: 30)
                        }
                        .buttonStyle(PressableButtonStyle())
                    } else {
                        MuscleIcon(group: exercise.muscleGroup, size: 28)
                    }
                }
                Text(entry.exercise?.name ?? "Exercice supprimé")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Menu {
                    if let demo = entry.exercise?.libraryEntry {
                        Button("Voir l'exécution", systemImage: "figure.strengthtraining.traditional") {
                            demoEntry = demo
                        }
                    }
                    if entry.exercise != nil {
                        Button("Remplacer l'exercice", systemImage: "arrow.triangle.2.circlepath") {
                            isReplacing = true
                        }
                    }
                    if canMoveUp {
                        Button("Monter", systemImage: "arrow.up") { onMove(-1) }
                    }
                    if canMoveDown {
                        Button("Descendre", systemImage: "arrow.down") { onMove(1) }
                    }
                    Button("Calculer les disques", systemImage: "circle.grid.2x1") {
                        onShowPlates(entry.orderedSets.last?.weight ?? 0)
                    }
                    Button("Retirer l'exercice", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) {
                            context.delete(entry)
                            try? context.save()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.vertical, 4)
                }
            }
            .textCase(nil)
            .padding(.bottom, 4)
            .sheet(item: $demoEntry) { demo in
                NavigationStack {
                    LibraryDetailView(entry: demo, showsAddButton: false)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("OK") { demoEntry = nil }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isReplacing) {
                if let current = entry.exercise {
                    ReplaceExerciseView(current: current) { replacement in
                        swap(current, for: replacement)
                    }
                }
            }
            .confirmationDialog(
                "Garder ce changement pour la prochaine fois ?",
                isPresented: Binding(get: { pendingSwap != nil }, set: { if !$0 { pendingSwap = nil } }),
                titleVisibility: .visible,
                presenting: pendingSwap
            ) { pending in
                Button("Remplacer aussi dans « \(pending.templates[0].name) »") {
                    pending.templates.forEach { $0.replace(pending.old, with: pending.new) }
                    try? context.save()
                }
                Button("Cette séance seulement", role: .cancel) {}
            } message: { pending in
                Text("\(pending.new.name) remplacera \(pending.old.name) dans le modèle.")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let target = entry.targetDescription {
                    Label("Objectif : \(target)", systemImage: "target")
                }
                if let note = entry.note, !note.isEmpty {
                    Label(note, systemImage: "lightbulb")
                }
                if let increment = entry.progressionIncrement, increment > 0 {
                    Label(
                        "Objectif en hausse : +\(increment.preciseKgText) par rapport à la dernière fois.",
                        systemImage: "arrow.up.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
                if let notes = entry.exercise?.notes, !notes.isEmpty {
                    Label(notes, systemImage: "note.text")
                }
            }
        }
    }
}

struct PendingSwap {
    let old: Exercise
    let new: Exercise
    let templates: [WorkoutTemplate]
}

extension WorkoutExerciseSection {
    func swap(_ old: Exercise, for new: Exercise) {
        guard let workout = entry.workout else { return }
        withAnimation(.snappy) {
            workout.replace(entry, with: new)
        }
        try? context.save()
        let templates = workout.templates(using: old, in: context)
        if !templates.isEmpty {
            // Let the replacement sheet close before asking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pendingSwap = PendingSwap(old: old, new: new, templates: templates)
            }
        }
    }
}

struct SetRow: View {
    let number: Int
    @Bindable var set: WorkoutSet
    var previous: WorkoutSet?
    var isRecord: Bool
    var referenceOneRepMax: Double? = nil
    var onCompleted: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(set.isCompleted ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.field))
                if isRecord {
                    Image(systemName: "trophy.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(number)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(set.isCompleted ? Color.white : Color.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: SetColumns.number, alignment: .leading)

            Button {
                if let targetReps = set.targetReps {
                    set.weight = set.targetWeight ?? set.weight
                    set.reps = targetReps
                } else if let previous {
                    set.weight = previous.weight
                    set.reps = previous.reps
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    if let targetReps = set.targetReps {
                        HStack(spacing: 3) {
                            Image(systemName: set.isCompleted && set.reachedTarget ? "checkmark.seal.fill" : "target")
                                .font(.caption2.weight(.bold))
                            Text(Self.text(weight: set.targetWeight ?? 0, reps: targetReps))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(set.isCompleted && set.reachedTarget ? Color.green : Color.accentColor)
                        if let previous {
                            Text("avant \(Self.text(weight: previous.weight, reps: previous.reps))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(previous.map { Self.text(weight: $0.weight, reps: $0.reps) } ?? "—")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(previous == nil && set.targetReps == nil)
            .accessibilityHint("Remplit la série avec l'objectif")

            TextField("0", value: $set.weight, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .modifier(SetFieldStyle())
                .frame(width: SetColumns.weight)

            TextField("0", value: $set.reps, format: .number)
                .keyboardType(.numberPad)
                .modifier(SetFieldStyle())
                .frame(width: SetColumns.reps)

            let estimate = RPE.estimate(weight: set.weight, reps: set.reps, reference: referenceOneRepMax)
            Menu {
                Picker("RPE", selection: $set.rpe) {
                    Text(estimate.map { "Calculé : ~\(RPE.label($0))" } ?? "Non noté").tag(Double?.none)
                    ForEach(RPE.values.reversed(), id: \.self) { value in
                        Text("\(RPE.label(value)) · \(RPE.meaning(value))").tag(Double?.some(value))
                    }
                }
            } label: {
                Text(set.rpe.map(RPE.label) ?? estimate.map { "~" + RPE.label($0) } ?? "–")
                    .font(.subheadline.weight(set.rpe == nil ? .regular : .semibold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(set.rpe.map(rpeColor) ?? Color.secondary)
                    .frame(width: SetColumns.rpe, height: 34)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityLabel("RPE")

            Button {
                withAnimation(.snappy) {
                    set.isCompleted.toggle()
                }
                if set.isCompleted { onCompleted() }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: set.isCompleted)
            }
            .buttonStyle(.plain)
            .frame(width: SetColumns.check)
            .sensoryFeedback(.selection, trigger: set.isCompleted)
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.success, trigger: isRecord) { _, isNowRecord in isNowRecord }
    }

    private static func text(weight: Double, reps: Int) -> String {
        weight > 0
            ? "\(weight.formatted(.number.precision(.fractionLength(0...2)))) × \(reps)"
            : "\(reps) reps"
    }

    private func rpeColor(_ rpe: Double) -> Color {
        switch rpe {
        case 9.5...: .red
        case 8.5..<9.5: .orange
        default: .green
        }
    }
}

private struct SetFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .padding(.vertical, 7)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct RestTimerBar: View {
    let endDate: Date
    let total: TimeInterval
    var onAddTime: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let left = max(0, endDate.timeIntervalSince(timeline.date))
            let remaining = Int(left.rounded(.up))
            let isOver = remaining == 0
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: total > 0 ? left / total : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: left)
                    Image(systemName: isOver ? "bell.fill" : "timer")
                        .font(.subheadline.bold())
                        .symbolEffect(.bounce, value: isOver)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 0) {
                    Text(isOver ? "C'est reparti !" : "Repos")
                        .font(.caption.weight(.semibold))
                        .opacity(0.85)
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }

                Spacer()

                Button(action: onAddTime) {
                    Text("+30 s")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                Button(action: onDismiss) {
                    Text(isOver ? "OK" : "Passer")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(Color(red: 0.84, green: 0.13, blue: 0.24))
                        .background(.white, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .foregroundStyle(.white)
            .padding(14)
            .glassSurface(
                in: RoundedRectangle(cornerRadius: 30, style: .continuous),
                tint: Theme.accentRed,
                fallback: Theme.gradient
            )
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .sensoryFeedback(.success, trigger: isOver) { _, nowOver in nowOver }
        }
    }
}

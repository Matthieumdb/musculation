import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var workout: Workout
    var onFinish: (WorkoutSummary) -> Void

    @AppStorage(AppSettings.restDurationKey) private var restDuration = AppSettings.defaultRestDuration
    @State private var restEndDate: Date?
    @State private var isPickingExercise = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false
    @State private var plateTarget: PlateTarget?

    var body: some View {
        List {
            Section {
                TextField("Nom de la séance", text: $workout.title)
                    .font(.headline)
                TimelineView(.periodic(from: workout.startedAt, by: 1)) { timeline in
                    LabeledContent(
                        "Durée",
                        value: Duration.seconds(max(0, timeline.date.timeIntervalSince(workout.startedAt)))
                            .formatted(.time(pattern: .hourMinuteSecond))
                    )
                    .monospacedDigit()
                }
            }

            let entries = workout.orderedExercises
            ForEach(entries) { entry in
                WorkoutExerciseSection(
                    entry: entry,
                    canMoveUp: entry.persistentModelID != entries.first?.persistentModelID,
                    canMoveDown: entry.persistentModelID != entries.last?.persistentModelID,
                    onMove: { workout.move(entry, by: $0) },
                    onSetCompleted: startRest,
                    onShowPlates: { plateTarget = PlateTarget(weight: $0) }
                )
            }

            Section {
                Button {
                    isPickingExercise = true
                } label: {
                    Label("Ajouter un exercice", systemImage: "plus.circle.fill")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if let restEndDate {
                RestTimerBar(
                    endDate: restEndDate,
                    onAddTime: { self.restEndDate = max(restEndDate, .now).addingTimeInterval(30) },
                    onDismiss: { self.restEndDate = nil }
                )
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
                workout.addExercise(exercise, in: context)
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

    private func startRest() {
        RestNotifier.requestAuthorization()
        restEndDate = .now.addingTimeInterval(TimeInterval(restDuration))
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

struct WorkoutExerciseSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var entry: WorkoutExercise
    var canMoveUp: Bool
    var canMoveDown: Bool
    var onMove: (Int) -> Void
    var onSetCompleted: () -> Void
    var onShowPlates: (Double) -> Void

    var body: some View {
        let previousBest = entry.previousBestOneRepMax
        Section {
            ForEach(Array(entry.orderedSets.enumerated()), id: \.element.id) { pair in
                let set = pair.element
                SetRow(
                    number: pair.offset + 1,
                    set: set,
                    isRecord: set.isCompleted && previousBest.map { set.estimatedOneRepMax > $0 } == true,
                    onCompleted: onSetCompleted
                )
                .contextMenu {
                    Button("Calculer les disques", systemImage: "circle.grid.2x1") {
                        onShowPlates(set.weight)
                    }
                }
            }
            .onDelete { offsets in
                let sets = entry.orderedSets
                offsets.map { sets[$0] }.forEach { context.delete($0) }
                try? context.save()
            }

            Button {
                let last = entry.orderedSets.last
                entry.addSet(reps: last?.reps ?? 10, weight: last?.weight ?? 0, in: context)
            } label: {
                Label("Ajouter une série", systemImage: "plus")
            }
        } header: {
            HStack {
                Text(entry.exercise?.name ?? "Exercice supprimé")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Menu {
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
                        context.delete(entry)
                        try? context.save()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(.vertical, 4)
                }
            }
            .textCase(nil)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if entry.isProgressionSuggested {
                    Label(
                        "Objectif atteint la dernière fois : charge augmentée de \(AppSettings.weightIncrement.kgText).",
                        systemImage: "arrow.up.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
                if let previous = entry.exercise?.history.first {
                    Text("Dernière fois : \(previous.summary)")
                }
                if let notes = entry.exercise?.notes, !notes.isEmpty {
                    Text(notes).italic()
                }
            }
        }
    }
}

struct SetRow: View {
    let number: Int
    @Bindable var set: WorkoutSet
    var isRecord: Bool
    var onCompleted: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isRecord {
                    Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                } else {
                    Text("\(number)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22)

            TextField("0", value: $set.weight, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
            Text("kg").foregroundStyle(.secondary)

            TextField("0", value: $set.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
            Text("reps").foregroundStyle(.secondary)

            Spacer()

            Button {
                set.isCompleted.toggle()
                if set.isCompleted { onCompleted() }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: set.isCompleted)
        }
        .sensoryFeedback(.success, trigger: isRecord) { _, isNowRecord in isNowRecord }
    }
}

struct RestTimerBar: View {
    let endDate: Date
    var onAddTime: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = max(0, Int(endDate.timeIntervalSince(timeline.date).rounded(.up)))
            HStack(spacing: 12) {
                Image(systemName: remaining == 0 ? "bell.fill" : "timer")
                Text(remaining == 0 ? "Repos terminé !" : String(format: "Repos %d:%02d", remaining / 60, remaining % 60))
                    .font(.headline.monospacedDigit())
                Spacer()
                Button("+30 s", action: onAddTime)
                    .buttonStyle(.bordered)
                Button(remaining == 0 ? "OK" : "Passer", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, 8)
            .sensoryFeedback(.success, trigger: remaining == 0) { _, isOver in isOver }
        }
    }
}

import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var workout: Workout

    @AppStorage("restDuration") private var restDuration = 90
    @State private var restEndDate: Date?
    @State private var isPickingExercise = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false

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

            ForEach(workout.orderedExercises) { entry in
                WorkoutExerciseSection(entry: entry, onSetCompleted: startRest)
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
        .navigationTitle("Séance en cours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Temps de repos", selection: $restDuration) {
                        ForEach([60, 90, 120, 180, 240], id: \.self) { seconds in
                            Text("Repos : \(restLabel(seconds))").tag(seconds)
                        }
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
        .confirmationDialog("Terminer la séance ?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button("Terminer") { workout.finish(in: context) }
        } message: {
            Text("Seules les séries cochées seront enregistrées.")
        }
        .confirmationDialog("Abandonner la séance ?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Abandonner", role: .destructive) { workout.discard(in: context) }
        } message: {
            Text("Toutes les données de cette séance seront supprimées.")
        }
    }

    private func startRest() {
        restEndDate = .now.addingTimeInterval(TimeInterval(restDuration))
    }

    private func restLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60)"
    }
}

struct WorkoutExerciseSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var entry: WorkoutExercise
    var onSetCompleted: () -> Void

    var body: some View {
        Section {
            ForEach(Array(entry.orderedSets.enumerated()), id: \.element.id) { pair in
                SetRow(number: pair.offset + 1, set: pair.element, onCompleted: onSetCompleted)
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
            if let previous = entry.exercise?.history.first {
                Text("Dernière fois : \(previous.summary)")
            }
        }
    }
}

struct SetRow: View {
    let number: Int
    @Bindable var set: WorkoutSet
    var onCompleted: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
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

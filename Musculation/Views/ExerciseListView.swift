import SwiftUI
import SwiftData

struct ExerciseListView: View {
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]
    @State private var search = ""
    @State private var editingExercise: Exercise?
    @State private var isAdding = false

    var body: some View {
        let sections = ExerciseSection.make(from: exercises, matching: search)
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.group.label) {
                        ForEach(section.exercises) { exercise in
                            Button {
                                editingExercise = exercise
                            } label: {
                                HStack(spacing: 12) {
                                    MuscleIcon(group: exercise.muscleGroup, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name)
                                        if !exercise.notes.isEmpty {
                                            Text(exercise.notes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .onDelete { offsets in
                            offsets.map { section.exercises[$0] }.forEach { context.delete($0) }
                            try? context.save()
                        }
                    }
                }
            }
            .overlay {
                if sections.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Rechercher")
            .navigationTitle("Exercices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ajouter", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(item: $editingExercise) { ExerciseEditView(exercise: $0) }
            .sheet(isPresented: $isAdding) { ExerciseEditView(exercise: nil) }
        }
    }
}

struct ExerciseEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise?

    @State private var name: String
    @State private var muscleGroup: MuscleGroup
    @State private var notes: String
    @State private var weightStep: Double?

    init(exercise: Exercise?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _muscleGroup = State(initialValue: exercise?.muscleGroup ?? .chest)
        _notes = State(initialValue: exercise?.notes ?? "")
        _weightStep = State(initialValue: exercise?.weightStep)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom de l'exercice", text: $name)
                Picker("Groupe musculaire", selection: $muscleGroup) {
                    ForEach(MuscleGroup.allCases) { group in
                        Text(group.label).tag(group)
                    }
                }
                Section {
                    let inferred = Equipment.infer(from: name)
                    Picker("Saut de charge", selection: $weightStep) {
                        Text("Auto : \(inferred.defaultStep.preciseKgText) (\(inferred.label))").tag(Double?.none)
                        ForEach(Equipment.stepOptions, id: \.self) { step in
                            Text(step.preciseKgText).tag(Double?.some(step))
                        }
                    }
                } header: {
                    Text("Progression")
                } footer: {
                    Text("Le plus petit poids que tu peux ajouter sur cet exercice. Quand tu atteins le haut de ta fourchette de reps, l'app ajoute environ \(AppSettings.progressionPercent.formatted()) % de la charge, arrondi à ce saut (au moins un saut).")
                }

                Section {
                    TextField("Réglages machine, consignes…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                } footer: {
                    if exercise != nil {
                        Text("Supprimer un exercice (glisser dans la liste) conserve tes séances passées.")
                    }
                }
            }
            .navigationTitle(exercise == nil ? "Nouvel exercice" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let exercise {
            exercise.name = trimmedName
            exercise.muscleGroup = muscleGroup
            exercise.notes = notes
            exercise.weightStep = weightStep
        } else {
            let exercise = Exercise(name: trimmedName, muscleGroup: muscleGroup, notes: notes)
            context.insert(exercise)
            exercise.weightStep = weightStep
        }
        try? context.save()
        dismiss()
    }
}

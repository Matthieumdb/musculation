import SwiftUI
import SwiftData

struct TemplateEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: WorkoutTemplate
    let isNew: Bool

    @State private var isPickingExercise = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") {
                    TextField("Ex. Push, Haut du corps…", text: $template.name)
                }

                Section("Exercices") {
                    ForEach(template.orderedItems) { item in
                        TemplateItemRow(item: item)
                    }
                    .onDelete { offsets in
                        let items = template.orderedItems
                        offsets.map { items[$0] }.forEach { context.delete($0) }
                        try? context.save()
                    }

                    Button {
                        isPickingExercise = true
                    } label: {
                        Label("Ajouter un exercice", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(isNew ? "Nouveau modèle" : "Modifier le modèle")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isNew)
            .toolbar {
                if isNew {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            context.delete(template)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if template.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            template.name = "Mon modèle"
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePickerView { exercise in
                    template.addItem(exercise, in: context)
                }
            }
        }
    }
}

private struct TemplateItemRow: View {
    @Bindable var item: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.exercise?.name ?? "Exercice supprimé")
                .font(.headline)
            Stepper("\(item.targetSets) séries", value: $item.targetSets, in: 1...10)
            if let minReps = item.minReps {
                Stepper("Reps min : \(minReps)", value: Binding(
                    get: { minReps },
                    set: { item.minReps = min($0, item.targetReps) }
                ), in: 1...50)
                Stepper("Reps max : \(item.targetReps)", value: Binding(
                    get: { item.targetReps },
                    set: { item.targetReps = max($0, minReps) }
                ), in: 1...50)
            } else {
                Stepper("\(item.targetReps) répétitions", value: $item.targetReps, in: 1...50)
            }
            if let restSeconds = item.restSeconds {
                Stepper("Repos : \(AppSettings.restLabel(restSeconds))", value: Binding(
                    get: { restSeconds },
                    set: { item.restSeconds = $0 }
                ), in: 30...300, step: 15)
            }
        }
    }
}

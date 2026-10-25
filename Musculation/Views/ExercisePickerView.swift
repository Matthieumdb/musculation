import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @State private var search = ""
    var onPick: (Exercise) -> Void

    var body: some View {
        let sections = ExerciseSection.make(from: exercises, matching: search)
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.group.label) {
                        ForEach(section.exercises) { exercise in
                            Button(exercise.name) {
                                onPick(exercise)
                                dismiss()
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .overlay {
                if sections.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
            .navigationTitle("Choisir un exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }
}

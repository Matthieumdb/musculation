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
                Section {
                    NavigationLink {
                        LibraryView(initialSearch: search) { exercise in
                            onPick(exercise)
                            dismiss()
                        }
                    } label: {
                        Label(
                            search.isEmpty ? "Chercher dans la bibliothèque" : "Chercher « \(search) » dans la bibliothèque",
                            systemImage: "books.vertical.fill"
                        )
                    }
                }
                ForEach(sections) { section in
                    Section(section.group.label) {
                        ForEach(section.exercises) { exercise in
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ExerciseIcon(exercise: exercise, size: 32)
                                    Text(exercise.name)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
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

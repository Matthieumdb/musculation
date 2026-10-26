import SwiftUI
import SwiftData

/// Alternatives that work the same muscle as `current`, from the user's exercises and the library.
struct ReplaceExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    let current: Exercise
    var onPick: (Exercise) -> Void

    @State private var equipment: String?
    @State private var search = ""
    @State private var detail: LibraryExercise?

    private static let equipmentFilters = ["barbell", "dumbbell", "machine", "cable", "body only"]

    private var currentEntry: LibraryExercise? { current.libraryEntry }

    /// Library muscles that count as "the same muscle".
    private var muscles: [String] {
        if let primary = currentEntry?.primary.first { return [primary] }
        switch current.muscleGroup {
        case .chest: return ["chest"]
        case .back: return ["lats", "middle back"]
        case .shoulders: return ["shoulders"]
        case .biceps: return ["biceps"]
        case .triceps: return ["triceps"]
        case .legs: return ["quadriceps", "hamstrings"]
        case .glutes: return ["glutes"]
        case .abs: return ["abdominals"]
        case .fullBody, .cardio: return []
        }
    }

    private var muscleTitle: String {
        muscles.isEmpty ? current.muscleGroup.label : muscles.map(ExerciseLibrary.muscleLabel).joined(separator: ", ")
    }

    private func passesEquipment(_ entry: LibraryExercise) -> Bool {
        guard let equipment else { return true }
        if equipment == "barbell" { return entry.equipment == "barbell" || entry.equipment == "e-z curl bar" }
        return entry.equipment == equipment
    }

    private var mine: [Exercise] {
        exercises
            .filter { $0.persistentModelID != current.persistentModelID }
            .filter { exercise in
                if let entry = exercise.libraryEntry {
                    return muscles.contains { entry.primary.contains($0) } && passesEquipment(entry)
                }
                return exercise.muscleGroup == current.muscleGroup && equipment == nil
            }
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var library: [LibraryExercise] {
        let taken = Set(exercises.compactMap { $0.libraryEntry?.id })
        let mechanic = currentEntry?.mechanic
        let levels = ["beginner": 0, "intermediate": 1, "expert": 2]
        return ExerciseLibrary.all
            .filter { entry in
                !taken.contains(entry.id)
                    && muscles.contains { entry.primary.contains($0) }
                    && passesEquipment(entry)
                    && entry.matches(search)
            }
            .sorted { a, b in
                let aSame = a.mechanic == mechanic, bSame = b.mechanic == mechanic
                if aSame != bSame { return aSame }
                let aLevel = levels[a.level] ?? 3, bLevel = levels[b.level] ?? 3
                if aLevel != bLevel { return aLevel < bLevel }
                return a.nameFR.localizedStandardCompare(b.nameFR) == .orderedAscending
            }
    }

    var body: some View {
        let mine = mine
        let library = library
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Tout", isOn: equipment == nil) { equipment = nil }
                            ForEach(Self.equipmentFilters, id: \.self) { option in
                                chip(ExerciseLibrary.equipmentLabel(option), isOn: equipment == option) {
                                    equipment = equipment == option ? nil : option
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Même muscle : \(muscleTitle)")
                        .textCase(nil)
                }

                if !mine.isEmpty {
                    Section("Tes exercices") {
                        ForEach(mine) { exercise in
                            row(
                                title: exercise.name,
                                subtitle: exercise.libraryEntry?.equipmentLabel ?? exercise.equipment.label.capitalized,
                                entry: exercise.libraryEntry,
                                fallback: exercise.muscleGroup
                            ) {
                                pick(exercise)
                            }
                        }
                    }
                }

                if !library.isEmpty {
                    Section("Bibliothèque") {
                        ForEach(library) { entry in
                            row(
                                title: entry.nameFR,
                                subtitle: "\(entry.equipmentLabel) · \(entry.levelLabel)",
                                entry: entry,
                                fallback: entry.muscleGroup
                            ) {
                                pick(entry)
                            }
                        }
                    }
                }
            }
            .overlay {
                if mine.isEmpty && library.isEmpty {
                    ContentUnavailableView(
                        "Aucune variante",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Essaie un autre matériel ou une autre recherche.")
                    )
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
            .navigationTitle("Remplacer \(current.name)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $detail) { entry in
                LibraryDetailView(entry: entry, showsAddButton: false)
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            pick(entry)
                        } label: {
                            Label("Choisir cet exercice", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.appSpring) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.card), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(
        title: String,
        subtitle: String,
        entry: LibraryExercise?,
        fallback: MuscleGroup,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            if let entry {
                Button {
                    detail = entry
                } label: {
                    ExerciseThumbnail(entry: entry, size: 40)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Voir l'exécution")
            } else {
                MuscleIcon(group: fallback, size: 40)
            }
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    private func pick(_ exercise: Exercise) {
        onPick(exercise)
        dismiss()
    }

    private func pick(_ entry: LibraryExercise) {
        let exercise = Exercise(name: entry.nameFR, muscleGroup: entry.muscleGroup)
        exercise.libraryId = entry.id
        context.insert(exercise)
        try? context.save()
        pick(exercise)
    }
}

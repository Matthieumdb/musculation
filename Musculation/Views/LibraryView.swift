import SwiftUI
import SwiftData

/// Browse the bundled exercise library. With `onPick`, choosing an exercise adds it to the workout.
struct LibraryView: View {
    var onPick: ((Exercise) -> Void)?

    @State private var search: String
    @State private var muscle: String?
    @State private var equipment: String?

    init(initialSearch: String = "", onPick: ((Exercise) -> Void)? = nil) {
        self.onPick = onPick
        _search = State(initialValue: initialSearch)
    }

    private var results: [LibraryExercise] {
        ExerciseLibrary.all.filter { entry in
            entry.matches(search)
                && (muscle.map { entry.primary.contains($0) } ?? true)
                && (equipment.map { entry.equipment == $0 } ?? true)
        }
    }

    var body: some View {
        let results = results
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterMenu(
                            title: muscle.map(ExerciseLibrary.muscleLabel) ?? "Muscle",
                            isActive: muscle != nil,
                            options: ExerciseLibrary.muscles,
                            label: ExerciseLibrary.muscleLabel,
                            selection: $muscle
                        )
                        filterMenu(
                            title: equipment.map(ExerciseLibrary.equipmentLabel) ?? "Matériel",
                            isActive: equipment != nil,
                            options: ExerciseLibrary.equipments,
                            label: ExerciseLibrary.equipmentLabel,
                            selection: $equipment
                        )
                        if muscle != nil || equipment != nil {
                            Button("Effacer") {
                                withAnimation(.snappy) {
                                    muscle = nil
                                    equipment = nil
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            } footer: {
                Text("\(results.count) exercice\(results.count > 1 ? "s" : "")")
            }

            ForEach(results) { entry in
                NavigationLink(value: entry) {
                    LibraryRow(entry: entry)
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Squat, curl, poulie…")
        .navigationTitle("Bibliothèque")
        .navigationDestination(for: LibraryExercise.self) { entry in
            LibraryDetailView(entry: entry, onPick: onPick)
        }
    }

    private func filterMenu(
        title: String,
        isActive: Bool,
        options: [String],
        label: @escaping (String) -> String,
        selection: Binding<String?>
    ) -> some View {
        Menu {
            Picker(title, selection: selection) {
                Text("Tous").tag(String?.none)
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(String?.some(option))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(isActive ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.card), in: Capsule())
        }
    }
}

private struct LibraryRow: View {
    let entry: LibraryExercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(entry: entry, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nameFR)
                    .lineLimit(2)
                Text("\(entry.primaryLabel) · \(entry.equipmentLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct LibraryDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var exercises: [Exercise]
    let entry: LibraryExercise
    var onPick: ((Exercise) -> Void)? = nil
    var showsAddButton = true

    @State private var justAdded = false

    private var existing: Exercise? {
        exercises.first { $0.libraryId == entry.id }
            ?? exercises.first { ExerciseLibrary.entry(for: $0)?.id == entry.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExerciseAnimationView(entry: entry)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.nameFR)
                        .font(.title2.bold())
                    Text(entry.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                FlowChips(items: tags)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Exécution").font(.headline)
                        Spacer()
                        if !entry.hasFrenchInstructions {
                            Text("en anglais")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(entry.displayInstructions.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(pair.offset + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Theme.gradient, in: Circle())
                            Text(pair.element)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()

                if !entry.secondary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Muscles secondaires").font(.headline)
                        Text(entry.secondary.map(ExerciseLibrary.muscleLabel).joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                Text("Illustrations : Free Exercise DB (domaine public).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(entry.nameFR)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if showsAddButton {
                addButton
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    private var tags: [String] {
        var tags = [entry.primaryLabel, entry.equipmentLabel, entry.levelLabel]
        if let mechanic = entry.mechanic {
            tags.append(mechanic == "compound" ? "Polyarticulaire" : "Isolation")
        }
        return tags
    }

    @ViewBuilder
    private var addButton: some View {
        if let onPick {
            Button {
                onPick(existing ?? addToMyExercises())
            } label: {
                Label("Ajouter à la séance", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else if existing != nil {
            Label(justAdded ? "Ajouté à tes exercices" : "Déjà dans tes exercices", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Button {
                withAnimation(.snappy) {
                    _ = addToMyExercises()
                    justAdded = true
                }
            } label: {
                Label("Ajouter à mes exercices", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func addToMyExercises() -> Exercise {
        let exercise = Exercise(name: entry.nameFR, muscleGroup: entry.muscleGroup)
        exercise.libraryId = entry.id
        context.insert(exercise)
        try? context.save()
        return exercise
    }
}

/// Small capsules that wrap onto several lines.
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.card, in: Capsule())
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += row.indices.isEmpty ? size.width : size.width + spacing
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

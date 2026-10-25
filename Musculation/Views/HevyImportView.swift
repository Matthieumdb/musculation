import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HevyImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]
    @Query private var existingWorkouts: [Workout]

    @State private var isPickingFile = false
    @State private var workouts: [HevyImport.ParsedWorkout] = []
    @State private var titles: [String] = []
    @State private var targets: [String: HevyImport.Target] = [:]
    @State private var choosingFor: ChoosingTitle?
    @State private var errorMessage: String?
    @State private var importedCount: Int?
    @State private var bodyWeights: [(date: Date, weight: Double)] = []
    @State private var importedWeights: Int?

    private struct ChoosingTitle: Identifiable {
        let title: String
        var id: String { title }
    }

    private var newWorkouts: [HevyImport.ParsedWorkout] {
        workouts.filter { parsed in
            !existingWorkouts.contains { abs($0.startedAt.timeIntervalSince(parsed.start)) < 60 }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !bodyWeights.isEmpty {
                    weightsSummary
                } else if workouts.isEmpty {
                    instructions
                } else {
                    summary
                    mapping
                }
            }
            .navigationTitle("Importer depuis Hevy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !bodyWeights.isEmpty {
                    Button {
                        importedWeights = HevyImport.importBodyWeights(bodyWeights, in: context)
                    } label: {
                        Label("Importer \(bodyWeights.count) pesées", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                } else if !workouts.isEmpty {
                    let count = newWorkouts.count
                    Button {
                        importedCount = HevyImport.importWorkouts(newWorkouts, targets: targets, in: context)
                    } label: {
                        Label(
                            count == 0 ? "Déjà importé" : "Importer \(count) séance\(count > 1 ? "s" : "")",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(count == 0)
                    .opacity(count == 0 ? 0.5 : 1)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $isPickingFile) {
                DocumentPicker(types: [.commaSeparatedText, .plainText, .text, .data]) { url in
                    load(.success(url))
                }
                .ignoresSafeArea()
            }
            .sheet(item: $choosingFor) { choosing in
                ExercisePickerView { exercise in
                    targets[choosing.title] = .existing(exercise.persistentModelID, name: exercise.name)
                }
            }
            .alert("Import impossible", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Pesées importées", isPresented: Binding(
                get: { importedWeights != nil },
                set: { if !$0 { importedWeights = nil } }
            )) {
                Button("OK") { dismiss() }
            } message: {
                let count = importedWeights ?? 0
                Text(count == 0
                    ? "Ces pesées étaient déjà dans l'app."
                    : "\(count) pesée\(count > 1 ? "s" : "") ajoutée\(count > 1 ? "s" : "") dans Progrès › Poids de corps.")
            }
            .alert("Import terminé", isPresented: Binding(
                get: { importedCount != nil },
                set: { if !$0 { importedCount = nil } }
            )) {
                Button("OK") { dismiss() }
            } message: {
                let count = importedCount ?? 0
                Text("\(count) séance\(count > 1 ? "s" : "") ajoutée\(count > 1 ? "s" : "") à ton historique.")
            }
        }
    }

    private var instructions: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.gradient)
                Text("Récupère tout ton historique Hevy")
                    .font(.title3.bold())
                step(1, "Dans Hevy, ouvre ton profil puis les réglages (roue dentée).")
                step(2, "Touche « Exporter et importer des données », puis « Exporter les séances ».")
                step(3, "Enregistre le fichier CSV dans Fichiers, puis choisis-le ici.")
                Text("Tu peux aussi importer l'export des mensurations de Hevy : tes pesées iront dans le suivi du poids de corps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Tes séances, exercices, charges et répétitions sont importés. Les séries d'échauffement sont ignorées, et une séance déjà présente n'est jamais importée deux fois.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    isPickingFile = true
                } label: {
                    Label("Choisir le fichier CSV", systemImage: "doc.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.gradient, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: some View {
        Section {
            let setCount = workouts.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
            HStack(spacing: 10) {
                StatTile(value: "\(workouts.count)", label: "Séances", symbol: "calendar", tint: .orange)
                StatTile(value: "\(titles.count)", label: "Exercices", symbol: "dumbbell.fill", tint: .blue)
                StatTile(value: "\(setCount)", label: "Séries", symbol: "list.number", tint: .green)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            if let first = workouts.first?.start, let last = workouts.last?.start {
                Text(rangeDescription(from: first, to: last))
            }
        }
    }

    private func rangeDescription(from first: Date, to last: Date) -> String {
        let range = "Du \(first.formatted(date: .abbreviated, time: .omitted)) au \(last.formatted(date: .abbreviated, time: .omitted))."
        let skipped = workouts.count - newWorkouts.count
        guard skipped > 0 else { return range }
        return range + " \(skipped) déjà dans l'app, ignorée\(skipped > 1 ? "s" : "")."
    }

    private var weightsSummary: some View {
        Section {
            ForEach(Array(bodyWeights.enumerated().reversed()), id: \.offset) { pair in
                LabeledContent(
                    pair.element.date.formatted(date: .abbreviated, time: .omitted),
                    value: pair.element.weight.preciseKgText
                )
            }
        } header: {
            Text("\(bodyWeights.count) pesées trouvées")
        } footer: {
            Text("Les jours où tu as déjà une pesée dans l'app sont ignorés.")
        }
    }

    private var mapping: some View {
        Section {
            ForEach(titles, id: \.self) { title in
                let target = targets[title] ?? .new(name: title)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Menu {
                        let suggestion = HevyImport.suggestedTarget(for: title, exercises: exercises)
                        if suggestion != target {
                            Button(suggestion.label, systemImage: "sparkles") { targets[title] = suggestion }
                        }
                        Button("Choisir un exercice…", systemImage: "list.bullet") {
                            choosingFor = ChoosingTitle(title: title)
                        }
                        Button("Créer « \(title) »", systemImage: "plus") { targets[title] = .new(name: title) }
                    } label: {
                        HStack {
                            Image(systemName: icon(for: target))
                                .foregroundStyle(Color.accentColor)
                            Text(target.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.body.weight(.medium))
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Correspondance des exercices")
        } footer: {
            Text("Relié à un de tes exercices, ton historique Hevy s'ajoute au sien (graphiques, records, charges proposées). « Nouveau » crée l'exercice.")
        }
    }

    private func icon(for target: HevyImport.Target) -> String {
        switch target {
        case .existing: "checkmark.circle.fill"
        case .library: "books.vertical.fill"
        case .new: "plus.circle"
        }
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw HevyImport.ImportError.notHevy
            }
            if let weights = HevyImport.parseBodyWeights(text) {
                guard !weights.isEmpty else { throw HevyImport.ImportError.empty }
                withAnimation(.snappy) { bodyWeights = weights.sorted { $0.date < $1.date } }
                return
            }
            let parsed = try HevyImport.parse(text)
            var seen = Set<String>()
            let names = parsed.flatMap { $0.exercises.map(\.title) }.filter { seen.insert($0).inserted }
            titles = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            targets = Dictionary(uniqueKeysWithValues: names.map {
                ($0, HevyImport.suggestedTarget(for: $0, exercises: exercises))
            })
            withAnimation(.snappy) {
                bodyWeights = []
                workouts = parsed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

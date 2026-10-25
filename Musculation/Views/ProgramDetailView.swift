import SwiftUI
import SwiftData

struct ProgramDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TrainingProgram.startDateKey) private var programStart: Double = 0
    let programName: String

    @State private var isConfirmingRemoval = false

    private var program: TrainingProgram? {
        TrainingProgram.all.first { $0.name == programName }
    }

    var body: some View {
        let phase = TrainingProgram.phase(startedAt: Date(timeIntervalSince1970: programStart))
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Semaine \(phase.week) sur \(TrainingProgram.cycleWeeks) · \(phase.title)")
                            .font(.headline)
                        Text(phase.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(1...TrainingProgram.cycleWeeks, id: \.self) { week in
                                Capsule()
                                    .fill(week <= phase.week ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.field))
                                    .frame(height: 6)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Semaines 1-2 : reprise. 3 à 6 : progression. 7 : surcharge. 8 : décharge, l'app réduit alors les séries de moitié.")
                }

                if let program {
                    Section("Règles") {
                        ForEach(program.rules, id: \.self) { rule in
                            Label(rule, systemImage: "checkmark.seal.fill")
                                .font(.subheadline)
                        }
                    }

                    ForEach(program.sessions) { session in
                        Section("\(session.day) · \(session.name)") {
                            ForEach(Array(session.exercises.enumerated()), id: \.offset) { pair in
                                let exercise = pair.element
                                HStack(alignment: .top, spacing: 12) {
                                    MuscleIcon(group: exercise.group, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name)
                                        Text("\(exercise.sets) × \(exercise.minReps)-\(exercise.maxReps) reps · repos \(AppSettings.restLabel(exercise.rest))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let note = exercise.note {
                                            Text(note)
                                                .font(.caption)
                                                .italic()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Recommencer le cycle à la semaine 1") {
                        programStart = Date.now.timeIntervalSince1970
                    }
                    Button("Arrêter le programme", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                } footer: {
                    Text("Les séances du programme sont des modèles : tu peux les modifier (appui sur une séance) sans casser le suivi.")
                }
            }
            .navigationTitle(programName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .confirmationDialog("Arrêter le programme ?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                Button("Arrêter", role: .destructive) {
                    TrainingProgram.uninstall(programName, in: context)
                    dismiss()
                }
            } message: {
                Text("Ses 5 modèles seront supprimés. Ton historique est conservé.")
            }
        }
    }
}

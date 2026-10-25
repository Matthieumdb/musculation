import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.restDurationKey) private var restDuration = AppSettings.defaultRestDuration
    @AppStorage(AppSettings.progressionPercentKey) private var progressionPercent = AppSettings.defaultProgressionPercent
    @AppStorage(AppSettings.barWeightKey) private var barWeight = AppSettings.defaultBarWeight

    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var pendingBackup: Backup?
    @State private var alertMessage: String?
    @State private var isImportingHevy = false
    @AppStorage(HealthSync.enabledKey) private var healthEnabled = false
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Temps de repos", selection: $restDuration) {
                        ForEach(AppSettings.restOptions, id: \.self) { seconds in
                            Text(AppSettings.restLabel(seconds)).tag(seconds)
                        }
                    }
                    Picker("Progression de charge", selection: $progressionPercent) {
                        ForEach(AppSettings.progressionOptions, id: \.self) { percent in
                            Text("+ \(percent.formatted()) %").tag(percent)
                        }
                    }
                    Picker("Barre", selection: $barWeight) {
                        ForEach(AppSettings.barOptions, id: \.self) { weight in
                            Text(weight == 0 ? "Sans barre" : weight.kgText).tag(weight)
                        }
                    }
                } header: {
                    Text("Entraînement")
                } footer: {
                    Text("Quand tu réussis toutes les répétitions cibles d'un modèle, la charge augmente d'environ ce pourcentage, arrondi au plus petit saut possible de l'exercice (réglable dans sa fiche).")
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Exporter mes données", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("Restaurer une sauvegarde", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Sauvegarde")
                } footer: {
                    Text("Tes données sont uniquement sur cet iPhone. Exporte-les de temps en temps vers Fichiers ou iCloud Drive, surtout avant de réinstaller l'app.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { healthEnabled },
                        set: { enable in
                            if enable { connectHealth() } else { healthEnabled = false }
                        }
                    )) {
                        Label("Apple Santé", systemImage: "heart.fill")
                    }
                    .disabled(!HealthSync.isAvailable)
                    if healthEnabled {
                        Button {
                            Task { await importHealthWeights() }
                        } label: {
                            Label("Importer mon poids depuis Santé", systemImage: "scalemass")
                        }
                    }
                } header: {
                    Text("Apple Santé")
                } footer: {
                    Text(healthMessage ?? "Chaque séance terminée est enregistrée dans Santé (musculation, durée, calories estimées), ainsi que tes pesées. Ton poids saisi dans Santé (balance connectée, autres apps) peut être récupéré ici.")
                }

                Section {
                    Button {
                        isImportingHevy = true
                    } label: {
                        Label("Importer depuis Hevy", systemImage: "arrow.down.doc")
                    }
                } header: {
                    Text("Autres apps")
                } footer: {
                    Text("Récupère tes séances et tes pesées Hevy à partir de leurs exports CSV.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $isImportingHevy) { HevyImportView() }
            .onAppear {
                exportURL = try? BackupService.exportFile(from: context)
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                do {
                    pendingBackup = try BackupService.read(result.get())
                } catch {
                    alertMessage = "Fichier de sauvegarde illisible."
                }
            }
            .confirmationDialog(
                "Remplacer toutes les données ?",
                isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remplacer", role: .destructive) { restore() }
            } message: {
                if let pendingBackup {
                    Text("La sauvegarde du \(pendingBackup.exportedAt.formatted(date: .long, time: .shortened)) contient \(pendingBackup.workouts.count) séances. Les données actuelles seront effacées.")
                }
            }
            .alert(
                alertMessage ?? "",
                isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
            ) {
                Button("OK") {}
            }
        }
    }

    private func connectHealth() {
        Task {
            if let error = await HealthSync.requestAccess() {
                healthMessage = "Connexion à Apple Santé impossible : \(error)"
                return
            }
            healthEnabled = true
            await importHealthWeights()
        }
    }

    @MainActor
    private func importHealthWeights() async {
        let added = await HealthSync.importBodyWeights(into: context)
        healthMessage = added == 0
            ? "Connecté à Apple Santé. Aucune nouvelle pesée à récupérer."
            : "Connecté à Apple Santé. \(added) pesée\(added > 1 ? "s" : "") récupérée\(added > 1 ? "s" : "")."
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private func restore() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        do {
            let active = try context.fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil }))
            guard active == 0 else {
                alertMessage = "Termine ou abandonne la séance en cours avant de restaurer."
                return
            }
            try BackupService.restore(backup, into: context)
            exportURL = try? BackupService.exportFile(from: context)
            alertMessage = "Sauvegarde restaurée."
        } catch {
            alertMessage = "La restauration a échoué."
        }
    }
}

import SwiftUI
import SwiftData

/// Top card of the workout tab: recovery score, tired muscles and the daily check-in.
struct RecoveryCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    @Query private var checkIns: [DailyCheckIn]
    @State private var isCheckingIn = false

    var body: some View {
        let today = checkIns.first { $0.day == DayKey.today }
        let muscles = Recovery.freshness(Array(workouts.prefix(20)))
        let score = Recovery.score(today, muscles: muscles)
        let tired = muscles.filter { $0.freshness < 0.95 }.sorted { $0.freshness < $1.freshness }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardTitle("Récupération", symbol: "heart.fill", tint: .green)
                Spacer()
                Button(today?.hasFeelings == true ? "Modifier" : "Faire le point") { isCheckingIn = true }
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(progress: Double(score.value) / 100, tint: score.tint, lineWidth: 9)
                    Text("\(score.value)")
                        .font(.display(24))
                        .contentTransition(.numericText())
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text(score.verdict).font(.headline)
                    Text(score.isComplete
                         ? (score.factors.isEmpty ? "Rien à signaler aujourd'hui." : score.factors.joined(separator: " · ").capitalizedFirst)
                         : "Selon tes dernières séances. Fais le point sur ta nuit pour un score complet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if tired.isEmpty {
                Label("Tous tes muscles sont reposés", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tired) { muscle in
                            HStack(spacing: 6) {
                                MuscleIcon(group: muscle.group, size: 22)
                                Text(muscle.group.label).font(.footnote)
                                Text("\(Int((muscle.freshness * 100).rounded())) %")
                                    .font(.footnote.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(muscle.freshness < 0.5 ? Color.red : Color.orange)
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 10)
                            .padding(.vertical, 4)
                            .background(Theme.field, in: Capsule())
                        }
                    }
                }
                Text("Fraîcheur musculaire : chaque série fatigue son muscle pendant environ 3 jours.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .sheet(isPresented: $isCheckingIn) {
            CheckInSheet(entry: DailyCheckIn.today(in: context))
        }
    }
}

/// Morning check-in, as in Bevel's journal.
struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var entry: DailyCheckIn

    private static let ratings = ["Très mauvaise", "Mauvaise", "Correcte", "Bonne", "Excellente"]
    private static let levels = ["Aucun", "Léger", "Moyen", "Fort", "Très fort"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Sommeil") {
                    Stepper(value: Binding(get: { entry.sleepHours ?? 7.5 }, set: { entry.sleepHours = $0 }), in: 2...12, step: 0.5) {
                        LabeledContent("Durée", value: (entry.sleepHours ?? 7.5).formatted(.number.precision(.fractionLength(0...1))) + " h")
                    }
                    rating("Qualité", value: $entry.sleepQuality)
                }
                Section("Ce matin") {
                    rating("Énergie", value: $entry.energy)
                    level("Courbatures", value: $entry.soreness)
                    level("Stress", value: $entry.stress)
                }
                Section {
                    Stepper("Eau : \(entry.water) verre\(entry.water > 1 ? "s" : "")", value: $entry.water, in: 0...20)
                    Stepper("Cafés : \(entry.caffeine)", value: $entry.caffeine, in: 0...10)
                    Stepper("Alcool hier soir : \(entry.alcohol) verre\(entry.alcohol > 1 ? "s" : "")", value: $entry.alcohol, in: 0...15)
                } header: {
                    Text("Habitudes")
                } footer: {
                    Text("Le journal montre ensuite ce qui aide ou freine ta récupération (Progrès > Journal).")
                }
                Section("Note") {
                    TextField("Douleur, maladie, voyage…", text: $entry.note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Faire le point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if entry.sleepHours == nil { entry.sleepHours = 7.5 }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func rating(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title, value: value.wrappedValue.map { Self.ratings[$0 - 1] } ?? "Non noté")
            Picker(title, selection: value) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func level(_ title: String, value: Binding<Int?>) -> some View {
        Picker(title, selection: value) {
            Text("Non noté").tag(Int?.none)
            ForEach(1...5, id: \.self) { Text(Self.levels[$0 - 1]).tag(Int?.some($0)) }
        }
    }
}

/// Past check-ins with their score, and what helps or hurts recovery.
struct CheckInHistoryView: View {
    @Query(sort: \DailyCheckIn.day, order: .reverse) private var checkIns: [DailyCheckIn]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]

    private struct Day: Identifiable {
        var entry: DailyCheckIn
        var score: Recovery.Score
        var id: String { entry.day }
    }

    private struct Insight: Identifiable {
        var text: String
        var delta: Int
        var id: String { text }
    }

    var body: some View {
        let days: [Day] = checkIns.filter(\.hasFeelings).prefix(60).map { entry -> Day in
            let morning = (DayKey.date(entry.day) ?? .now).addingTimeInterval(9 * 3600)
            return Day(entry: entry, score: Recovery.score(entry, muscles: Recovery.freshness(workouts, now: morning)))
        }
        let insights = Self.insights(days)

        List {
            if !insights.isEmpty {
                Section {
                    ForEach(insights) { insight in
                        Label {
                            Text(insight.text)
                        } icon: {
                            Text("\(insight.delta > 0 ? "+" : "")\(insight.delta)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(insight.delta >= 0 ? Color.green : Color.red)
                        }
                    }
                } header: {
                    Text("Ce qui compte pour toi")
                } footer: {
                    Text("Écart de score moyen, d'après tes propres journées.")
                }
            }
            Section("Journées") {
                ForEach(days) { day in
                    HStack(spacing: 12) {
                        Text("\(day.score.value)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(day.score.tint.gradient, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text((DayKey.date(day.entry.day) ?? .now).formatted(.dateTime.weekday(.wide).day().month()).capitalized)
                            Text(summary(day.entry)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if days.isEmpty {
                    Text("Fais le point chaque matin depuis l'onglet Séance : ton historique apparaîtra ici.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Journal")
    }

    private func summary(_ e: DailyCheckIn) -> String {
        var parts: [String] = []
        if let h = e.sleepHours { parts.append("\(h.formatted(.number.precision(.fractionLength(0...1)))) h de sommeil") }
        if e.water > 0 { parts.append("\(e.water) verres d'eau") }
        if e.alcohol > 0 { parts.append("alcool") }
        if !e.note.isEmpty { parts.append(e.note) }
        return parts.joined(separator: " · ")
    }

    /// Compares the average score of days with and without a habit, once each side has 3 days.
    private static func insights(_ days: [Day]) -> [Insight] {
        func compare(_ text: String, _ test: (DailyCheckIn) -> Bool?) -> Insight? {
            let yes = days.filter { test($0.entry) == true }.map(\.score.value)
            let no = days.filter { test($0.entry) == false }.map(\.score.value)
            guard yes.count >= 3, no.count >= 3 else { return nil }
            let delta = yes.reduce(0, +) / yes.count - no.reduce(0, +) / no.count
            return Insight(text: text, delta: delta)
        }
        return [
            compare("Dormir 7 h ou plus") { $0.sleepHours.map { $0 >= 7 } },
            compare("Boire de l'alcool la veille") { $0.alcohol > 0 },
            compare("Boire au moins 6 verres d'eau") { $0.water >= 6 },
            compare("Plus de 2 cafés") { $0.caffeine > 2 },
        ].compactMap { $0 }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

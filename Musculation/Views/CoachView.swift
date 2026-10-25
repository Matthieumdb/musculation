import SwiftUI
import SwiftData

/// Compact coach summary for the workout tab.
struct CoachCard: View {
    let report: Coach.Report
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ton coach").font(.headline)
                        Text(report.headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                ForEach(report.insights.prefix(2)) { insight in
                    InsightRow(insight: insight, compact: true)
                }
            }
            .card()
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(.primary)
    }
}

struct CoachView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    @State private var demo: LibraryExercise?

    var body: some View {
        let report = Coach.analyze(Array(workouts.prefix(120)))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(report.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    section("À faire la prochaine fois", report.insights.filter { $0.kind == .action })
                    section("Attention", report.insights.filter { $0.kind == .warning })
                    section("Points forts", report.insights.filter { $0.kind == .win })
                    section("Bon à savoir", report.insights.filter { $0.kind == .info })

                    if report.insights.isEmpty {
                        ContentUnavailableView(
                            "Pas encore assez de données",
                            systemImage: "sparkles",
                            description: Text("Après quelques séances, je repère tes progrès, ce qui stagne et l'équilibre de ton entraînement.")
                        )
                    }

                    Text("Analyse faite sur ton iPhone à partir de tes 10 dernières semaines : progression du 1RM estimé, RPE (noté ou calculé), séries par muscle, équilibre poussée et tirage, régularité. Ce sont des repères généraux, pas un avis médical.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .background { AppBackground() }
            .navigationTitle("Ton coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(item: $demo) { entry in
                NavigationStack {
                    LibraryDetailView(entry: entry, showsAddButton: false)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ insights: [CoachInsight]) -> some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold())
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 10) {
                        InsightRow(insight: insight, compact: false)
                        if let entry = insight.exercise?.libraryEntry {
                            Button {
                                demo = entry
                            } label: {
                                Label("Voir l'exécution", systemImage: "play.rectangle")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .card()
                }
            }
        }
    }
}

private struct InsightRow: View {
    let insight: CoachInsight
    var compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(insight.kind.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(insight.message)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: !compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

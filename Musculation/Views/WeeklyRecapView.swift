import SwiftUI
import SwiftData
import Charts

/// Sunday recap: training, records, food and body over one week, with the weeks before.
struct WeeklyRecapView: View {
    @Environment(NutritionStore.self) private var nutrition
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    @Query private var weights: [BodyWeightEntry]
    @Query private var checkIns: [DailyCheckIn]
    @State private var weeksBack: Int

    /// `weeksBack` 1 opens on last week, as on a Monday.
    init(weeksBack: Int = 0) {
        _weeksBack = State(initialValue: weeksBack)
    }

    private var week: DateInterval {
        let date = Calendar.current.date(byAdding: .weekOfYear, value: -weeksBack, to: .now) ?? .now
        return WeeklyRecap.week(containing: date)
    }

    var body: some View {
        let recap = WeeklyRecap.make(
            week: week,
            workouts: workouts,
            logs: nutrition.state.logs,
            targets: nutrition.settings.baseTargets,
            weights: weights,
            checkIns: checkIns
        )

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(recap.week))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(recap.headline)
                        .font(.display(26, relativeTo: .title))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Entraînement") {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        figure("\(recap.workouts)", "séance\(recap.workouts > 1 ? "s" : "")", delta: comparison(Double(recap.workouts), Double(recap.previousWorkouts), unit: ""), tint: .orange)
                        figure(recap.volume.kgText, "soulevés", delta: comparison(recap.volume, recap.previousVolume, unit: "%"), tint: .green)
                    }
                    GridRow {
                        figure(durationText(recap.duration), "d'entraînement", delta: nil, tint: .blue)
                        figure("\(recap.sets)", "séries", delta: nil, tint: .purple)
                    }
                }
                .padding(.vertical, 6)
            }

            if !recap.records.isEmpty {
                Section("Records") {
                    ForEach(recap.records) { record in
                        LabeledContent {
                            Text("+\(Int(((record.oneRepMax / record.previous - 1) * 100).rounded())) %")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.green)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.exercise)
                                    Text("1RM estimé \(record.oneRepMax.kgText), avant \(record.previous.kgText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            }
                        }
                    }
                }
            }

            if !recap.muscles.isEmpty {
                Section {
                    Chart(recap.muscles) { muscle in
                        BarMark(x: .value("Séries", muscle.sets), y: .value("Muscle", muscle.group.label))
                            .foregroundStyle(muscle.group.color.gradient)
                            .annotation(position: .trailing) {
                                Text("\(muscle.sets)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(recap.muscles.count) * 30 + 10)
                    .padding(.vertical, 6)
                } header: {
                    Text("Séries par muscle")
                } footer: {
                    Text("Entre \(Coach.weeklySetRange.lowerBound) et \(Coach.weeklySetRange.upperBound) séries par muscle et par semaine suffisent pour progresser.")
                }
            }

            Section {
                if let kcal = recap.averageKcal, let protein = recap.averageProtein {
                    LabeledContent("Calories par jour", value: "\(Int(kcal.rounded())) / \(Int(recap.targetKcal.rounded())) kcal")
                    LabeledContent("Protéines par jour", value: "\(Int(protein.rounded())) / \(Int(recap.targetProtein.rounded())) g")
                } else {
                    Text("Aucun repas noté cette semaine.").foregroundStyle(.secondary)
                }
                if let water = recap.averageWater {
                    LabeledContent("Eau par jour", value: "\(water.formatted(.number.precision(.fractionLength(0...1)))) verres")
                }
            } header: {
                Text("Alimentation")
            } footer: {
                if recap.loggedDays > 0 {
                    Text("Moyenne sur \(recap.loggedDays) jour\(recap.loggedDays > 1 ? "s" : "") noté\(recap.loggedDays > 1 ? "s" : "").")
                }
            }

            if recap.weightEnd != nil || recap.averageSleep != nil {
                Section("Corps et récupération") {
                    if let end = recap.weightEnd {
                        LabeledContent("Poids") {
                            HStack(spacing: 6) {
                                Text(end.kgText)
                                if let start = recap.weightStart, abs(end - start) >= 0.05 {
                                    Text("\(end > start ? "+" : "−")\(abs(end - start).formatted(.number.precision(.fractionLength(1)))) kg")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let sleep = recap.averageSleep {
                        LabeledContent("Sommeil moyen", value: "\(sleep.formatted(.number.precision(.fractionLength(0...1)))) h")
                    }
                }
            }
        }
        .navigationTitle("Bilan de la semaine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Semaine précédente", systemImage: "chevron.left") { withAnimation(.appEase) { weeksBack += 1 } }
                Button("Semaine suivante", systemImage: "chevron.right") { withAnimation(.appEase) { weeksBack -= 1 } }
                    .disabled(weeksBack == 0)
            }
        }
    }

    private func title(_ week: DateInterval) -> String {
        if weeksBack == 0 { return "Cette semaine" }
        if weeksBack == 1 { return "La semaine dernière" }
        let end = week.end.addingTimeInterval(-1)
        return "Du \(week.start.formatted(.dateTime.day().month())) au \(end.formatted(.dateTime.day().month()))"
    }

    private func figure(_ value: String, _ label: String, delta: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.display(24))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let delta {
                Text(delta).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "+2 vs sem. passée" or "+12 % vs sem. passée"
    private func comparison(_ value: Double, _ previous: Double, unit: String) -> String? {
        guard previous > 0 else { return nil }
        let change = unit == "%" ? (value / previous - 1) * 100 : value - previous
        let rounded = Int(change.rounded())
        guard rounded != 0 else { return "comme la semaine d'avant" }
        return "\(rounded > 0 ? "+" : "−")\(abs(rounded))\(unit.isEmpty ? "" : " \(unit)") vs semaine d'avant"
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }
}

/// Shown on the workout tab from Sunday afternoon to Monday, as a way into the recap.
struct WeeklyRecapCard: View {
    var body: some View {
        NavigationLink {
            // On Monday the week to look back on is the one that just ended
            WeeklyRecapView(weeksBack: Calendar.current.component(.weekday, from: .now) == 2 ? 1 : 0)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ton bilan de la semaine est prêt").font(.headline)
                    Text("Séances, records, alimentation et poids").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    static var isRecapTime: Bool {
        let now = Date.now
        let weekday = Calendar.current.component(.weekday, from: now)
        let hour = Calendar.current.component(.hour, from: now)
        return (weekday == 1 && hour >= 14) || weekday == 2
    }
}

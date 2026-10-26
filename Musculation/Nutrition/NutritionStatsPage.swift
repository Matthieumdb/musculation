import SwiftUI
import SwiftData
import Charts

/// A day counts once it has a logged meal. On target: 90–105 % of calories and at least 90 % of protein.
struct NutritionStatsPage: View {
    @Environment(NutritionStore.self) private var store
    @Query(sort: \BodyWeightEntry.date) private var entries: [BodyWeightEntry]

    private struct Bar: Identifiable {
        var date: Date
        var value: Double
        var highlighted: Bool
        var id: Date { date }
    }

    private struct WeekRow: Identifiable {
        var from: String
        var kcal: Double?
        var p: Double?
        var onTarget: Int
        var weight: Double?
        var id: String { from }
    }

    var body: some View {
        @Bindable var store = store
        let n = store.state.statPeriod
        let weights = NutritionStore.weightsByDay(entries)
        let settings = store.settings
        let t = settings.dayTargets
        let tdee: Double? = settings.manual.on ? nil : settings.computedTargets().tdee
        let all = store.dayStats(n, weights: weights)
        let logged = all.filter(\.logged)

        VStack(alignment: .leading, spacing: 24) {
            Picker("Période", selection: $store.state.statPeriod) {
                Text("7 jours").tag(7)
                Text("30 jours").tag(30)
                Text("3 mois").tag(90)
            }
            .pickerStyle(.segmented)

            if logged.isEmpty && !all.contains(where: { $0.weight != nil }) {
                EmptyCardContent(symbol: "chart.bar.fill", title: "Pas encore de données",
                                 message: "Note tes repas dans Aujourd'hui : tes stats apparaîtront ici dès le premier jour.")
                    .card()
            } else {
                content(n: n, all: all, logged: logged, t: t, tdee: tdee, weights: weights)
            }
        }
    }

    @ViewBuilder
    private func content(n: Int, all: [DayStat], logged: [DayStat], t: Macros, tdee: Double?, weights: [String: Double]) -> some View {
        let avg = logged.isEmpty ? Macros.zero : logged.reduce(Macros.zero) { $0 + $1.macros } * (1 / Double(logged.count))
        let on = all.filter { $0.onTarget(t) }.count
        // Weight: average of the first 7 days of the period against the last 7
        let ws = all.filter { $0.weight != nil }
        let half = min(7, n / 2)
        let wa = all.prefix(half).compactMap(\.weight), wb = all.suffix(half).compactMap(\.weight)
        let dW: Double? = n >= 14 && wa.count >= 2 && wb.count >= 2
            ? wb.reduce(0, +) / Double(wb.count) - wa.reduce(0, +) / Double(wa.count)
            : (ws.count >= 2 ? (ws.last!.weight! - ws.first!.weight!) : nil)
        let deficit: Double? = tdee != nil && !logged.isEmpty ? tdee! - avg.kcal : nil
        let fatKg = (deficit ?? 0) * Double(logged.count) / 7700
        let long = store.dayStats(98, weights: weights)
        let streaks = Self.streaks(long, t: t)

        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(value: logged.isEmpty ? "—" : "\(Int(avg.kcal.rounded()))", label: "kcal / jour · cible \(Int(t.kcal))", symbol: "flame.fill", tint: Theme.calories)
            StatTile(value: logged.isEmpty ? "—" : "\(Int(avg.p.rounded())) g", label: "protéines / jour · cible \(Int(t.p)) g", symbol: "bolt.fill", tint: Theme.protein)
            StatTile(value: "\(on)", label: "jours dans la cible sur \(logged.count) notés", symbol: "target", tint: .green)
            StatTile(value: "\(logged.count)", label: "jours notés sur \(n)", symbol: "calendar", tint: .teal)
            StatTile(value: deficit.map { ($0 >= 0 ? "−" : "+") + "\(Int(abs($0).rounded()))" } ?? "—",
                     label: deficit.map { $0 > 0 ? "kcal / j · ≈ \(fatKg.kgText) de gras" : "kcal / j · surplus" } ?? "déficit moyen",
                     symbol: "chart.line.downtrend.xyaxis", tint: .purple)
            StatTile(value: dW.map { ($0 > 0 ? "+" : "") + $0.kgText } ?? "—",
                     label: dW == nil ? "pas assez de pesées" : (ws.last?.weight).map { "poids · \($0.kgText)" } ?? "poids",
                     symbol: "scalemass.fill", tint: .indigo)
        }

        Label("Série en cours : \(streaks.current) jour\(streaks.current > 1 ? "s" : "") dans la cible · record \(streaks.best)", systemImage: "flame")
            .font(.footnote)
            .foregroundStyle(.secondary)

        chartSection(n > 30 ? "Calories par semaine (moyenne / jour)" : "Calories par jour",
                     bars: bars(all, n: n, t: t) { $0.kcal }, target: t.kcal, tint: Theme.calories, unit: "kcal")
        chartSection(n > 30 ? "Protéines par semaine (moyenne / jour)" : "Protéines par jour",
                     bars: bars(all, n: n, t: t) { $0.p }, target: t.p, tint: Theme.protein, unit: "g")

        macroSplit(avg)
        weekTable(long: long, n: n, t: t)
    }

    private func bars(_ all: [DayStat], n: Int, t: Macros, value: (Macros) -> Double) -> [Bar] {
        if n > 30 {
            return stride(from: 0, to: all.count, by: 7).map { k in
                let chunk = Array(all[k..<min(k + 7, all.count)])
                let logged = chunk.filter(\.logged)
                let v = logged.isEmpty ? 0 : logged.reduce(0) { $0 + value($1.macros) } / Double(logged.count)
                return Bar(date: chunk[0].date, value: v, highlighted: !logged.isEmpty)
            }
        }
        return all.map { Bar(date: $0.date, value: value($0.macros), highlighted: $0.onTarget(t)) }
    }

    private func chartSection(_ title: String, bars: [Bar], target: Double, tint: Color, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title)
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(bars) { bar in
                        BarMark(x: .value("Jour", bar.date, unit: .day), y: .value(unit, bar.value))
                            .foregroundStyle(tint.opacity(bar.highlighted ? 1 : 0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    RuleMark(y: .value("Cible", target))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("cible \(Int(target)) \(unit)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartYScale(domain: 0...max(target * 1.25, bars.map(\.value).max() ?? 0, 1))
                .frame(height: 170)
                Text("Pointillés = ta cible · barre foncée = jour dans la cible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private func macroSplit(_ avg: Macros) -> some View {
        let parts: [(String, Double, Color)] = [("Prot.", avg.p * 4, Theme.protein), ("Gluc.", avg.c * 4, Theme.carbs), ("Lip.", avg.f * 9, Theme.fat)]
        let sum = max(parts.reduce(0) { $0 + $1.1 }, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Répartition moyenne des calories")
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { proxy in
                    HStack(spacing: 3) {
                        ForEach(parts, id: \.0) { part in
                            Capsule().fill(part.2.gradient).frame(width: max(0, proxy.size.width * part.1 / sum - 3))
                        }
                    }
                }
                .frame(height: 14)
                HStack(spacing: 16) {
                    ForEach(parts, id: \.0) { part in
                        HStack(spacing: 6) {
                            Circle().fill(part.2).frame(width: 8, height: 8)
                            Text("\(part.0) \(Int((part.1 / sum * 100).rounded())) %").font(.subheadline)
                        }
                    }
                }
            }
            .card()
        }
    }

    private func weekTable(long: [DayStat], n: Int, t: Macros) -> some View {
        let count = max(1, Int((Double(n) / 7).rounded()))
        let rows: [WeekRow] = (0..<count).map { k in
            let chunk = Array(long[(long.count - 7 * (k + 1))..<(long.count - 7 * k)])
            let logged = chunk.filter(\.logged)
            let w = chunk.compactMap(\.weight)
            return WeekRow(
                from: chunk[0].day,
                kcal: logged.isEmpty ? nil : logged.reduce(0) { $0 + $1.macros.kcal } / Double(logged.count),
                p: logged.isEmpty ? nil : logged.reduce(0) { $0 + $1.macros.p } / Double(logged.count),
                onTarget: chunk.filter { $0.onTarget(t) }.count,
                weight: w.isEmpty ? nil : w.reduce(0, +) / Double(w.count)
            )
        }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Bilan semaine par semaine")
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        ForEach(["Semaine", "kcal", "Prot.", "Cible", "Poids"], id: \.self) {
                            Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    ForEach(rows) { row in
                        GridRow {
                            Text("du \(shortDate(row.from))")
                            Text(row.kcal.map { "\(Int($0.rounded()))" } ?? "—")
                            Text(row.p.map { "\(Int($0.rounded())) g" } ?? "—")
                            Text("\(row.onTarget)/7")
                            Text(row.weight.map(\.kgText) ?? "—")
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                    }
                }
                Text("Dans la cible = calories entre 90 et 105 % de ta cible et protéines ≥ 90 %.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private func shortDate(_ day: String) -> String {
        DayKey.date(day)?.formatted(.dateTime.day().month(.twoDigits)) ?? day
    }

    /// Current and best runs of days on target, over 14 weeks.
    private static func streaks(_ days: [DayStat], t: Macros) -> (current: Int, best: Int) {
        var best = 0, run = 0
        for d in days {
            run = d.onTarget(t) ? run + 1 : 0
            best = max(best, run)
        }
        var current = 0
        for i in days.indices.reversed() {
            if days[i].onTarget(t) { current += 1 }
            else if i < days.count - 1 || days[i].logged { break }
        }
        return (current, best)
    }
}

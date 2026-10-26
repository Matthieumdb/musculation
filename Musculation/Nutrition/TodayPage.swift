import SwiftUI
import SwiftData
import Charts

/// Three blocks: the day and the meal at the top, what you eat, then weight and log.
struct TodayPage: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DayCard()
            if let doses = session.doses, doses.count == store.state.cart.count {
                DosesCard(doses: doses)
            } else {
                MealCard()
            }
            JournalCard()
        }
    }
}

// MARK: - Day and meal

private struct DayCard: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session

    var body: some View {
        let t = store.settings.dayTargets, e = store.eaten()
        let left = Int((t.kcal - e.kcal).rounded())
        let protLeft = max(0, Int((t.p - e.p).rounded()))
        let alert = Calendar.current.component(.hour, from: .now) >= 18 && protLeft > 40
        let slots = store.settings.slotTargets
        let selected = slots.first { $0.id == session.slotId } ?? slots.first

        VStack(alignment: .leading, spacing: 16) {
            CardTitle("Calories", symbol: "flame.fill", tint: Theme.calories)
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: t.kcal > 0 ? e.kcal / t.kcal : 0, tint: left < 0 ? Color.red : Theme.calories, lineWidth: 14)
                    VStack(spacing: 0) {
                        Text("\(abs(left))")
                            .font(.display(26))
                            .contentTransition(.numericText())
                        Text(left >= 0 ? "kcal restantes" : "kcal en trop")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, height: 104)

                VStack(spacing: 10) {
                    ForEach([MacroKey.p, .c, .f]) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(key.label).font(.subheadline)
                                Spacer()
                                Text("\(Int(e[key].rounded()))/\(Int(t[key])) g")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressBar(progress: t[key] > 0 ? e[key] / t[key] : 0, tint: key.color, height: 5)
                        }
                    }
                }
            }

            if slots.count > 1 {
                Picker("Repas", selection: Binding(
                    get: { selected?.id ?? "" },
                    set: { id in
                        withAnimation(.appEase) {
                            session.slotId = id
                            if session.doses != nil {
                                session.doses = PortionSolver.solve(store.state.cart, target: store.remaining(for: id))
                            }
                        }
                    }
                )) {
                    ForEach(slots) { Text($0.label).tag($0.id) }
                }
                .pickerStyle(.segmented)
            }

            if let selected {
                let rem = store.remaining(for: selected.id)
                Text("Reste pour \(selected.label.lowercased()) : **\(Int(rem.kcal)) kcal** · P \(Int(rem.p)) · G \(Int(rem.c)) · L \(Int(rem.f)) g")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if let training = store.training {
                Label(training.trained
                      ? "Jour de séance : +\(Int(training.kcal)) kcal, en glucides"
                      : "Jour de repos : \(Int(training.kcal)) kcal pour équilibrer tes séances de la semaine",
                      systemImage: training.trained ? "dumbbell.fill" : "bed.double.fill")
                    .font(.footnote)
                    .foregroundStyle(training.trained ? Color.green : Color.secondary)
            }

            if alert {
                Label("Il te manque \(protLeft) g de protéines ce soir : un skyr, du poulet ou une dose de whey.", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .card()
    }
}

// MARK: - Meal

private struct MealCard: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session

    var body: some View {
        let cart = store.state.cart

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle("Ce que tu manges", symbol: "fork.knife", tint: Theme.calories)
                Spacer()
                if !cart.isEmpty {
                    Text("\(cart.count) produit\(cart.count > 1 ? "s" : "")").font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let error = session.mealError { InlineError(text: error) }

            if cart.isEmpty {
                Text("Scanne tes produits ou touche un aliment, puis Calculer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cart.enumerated()), id: \.element.id) { index, _ in
                        if index > 0 { Divider().padding(.leading, 52) }
                        CartRow(index: index)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickFoods) { food in
                        Button {
                            withAnimation(.appSpring) {
                                session.doses = nil
                                store.addToCart(Product(food: food))
                            }
                        } label: {
                            Label(food.shortName, systemImage: "plus")
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.field, in: Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .scrollClipDisabled()
        }
        .card()
    }

    private var quickFoods: [Food] {
        let s = store.settings
        let liked = NutritionData.foods.filter { s.pref($0) == 1 && !NutritionData.quick.contains($0.id) }.map(\.id)
        return (NutritionData.quick + liked).compactMap { NutritionData.food($0) }.filter { s.allowed($0) }
    }
}

private struct CartRow: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    let index: Int

    @State private var isEditingGrams = false
    @State private var grams: Double?

    var body: some View {
        if store.state.cart.indices.contains(index) {
            let item = store.state.cart[index]
            HStack(spacing: 12) {
                ProductThumb(product: item, grade: store.settings.score(item).grade, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    MacroMixBar(n: item.n)
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Quantité calculée", systemImage: "wand.and.stars") { setFixed(nil) }
                    Button("Fixer la quantité…", systemImage: "scalemass") {
                        grams = item.fixed ?? item.unit?.grams ?? 100
                        isEditingGrams = true
                    }
                    Divider()
                    Button("Retirer", systemImage: "trash", role: .destructive) {
                        withAnimation(.appSpring) {
                            session.doses = nil
                            _ = store.state.cart.remove(at: index)
                        }
                    }
                } label: {
                    Text(item.fixed.map { "\(Int($0)) g" } ?? "auto")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.field, in: Capsule())
                }
                .foregroundStyle(item.fixed == nil ? Color.secondary : Color.primary)
            }
            .padding(.vertical, 8)
            .alert("Quantité fixe", isPresented: $isEditingGrams) {
                TextField("Grammes", value: $grams, format: .number).keyboardType(.numberPad)
                Button("Annuler", role: .cancel) {}
                Button("OK") { setFixed(max(0, grams ?? 0)) }
            } message: {
                Text(item.name)
            }
        }
    }

    private func setFixed(_ value: Double?) {
        guard store.state.cart.indices.contains(index) else { return }
        session.doses = nil
        store.state.cart[index].fixed = value
    }
}

// MARK: - Result

private struct DosesCard: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    let doses: [Double]

    var body: some View {
        let cart = store.state.cart
        let total = PortionSolver.totals(cart, grams: doses)
        let target = store.remaining(for: session.slotId)
        let worst = MacroKey.allCases.map { k in (k, target[k] > 0 ? (total[k] - target[k]) / target[k] : 0) }
            .max { abs($0.1) < abs($1.1) } ?? (.kcal, 0)
        let onTarget = abs(worst.1) <= 0.1

        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Tes doses à peser", symbol: "scalemass.fill")
            Label(onTarget ? "Pile dans tes objectifs"
                  : worst.1 < 0 ? "Il manque des \(worst.0.label.lowercased())"
                  : "Trop de \(worst.0.label.lowercased()) : fixe une quantité plus bas",
                  systemImage: onTarget ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(onTarget ? Color.green : Color.orange)

            VStack(spacing: 0) {
                ForEach(Array(cart.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().padding(.leading, 52) }
                    let g = doses[i]
                    HStack(spacing: 12) {
                        ProductThumb(product: item, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let note = note(item, g) {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("\(Int(g)) g")
                            .font(.display(22))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(g == 0 ? Color.secondary : Color.accentColor)
                    }
                    .padding(.vertical, 8)
                }
            }

            HStack(spacing: 0) {
                ForEach(MacroKey.allCases) { key in
                    VStack(spacing: 2) {
                        Text("\(Int(total[key].rounded()))").font(.subheadline.weight(.semibold)).foregroundStyle(key.color)
                        Text("/ \(Int(target[key].rounded())) \(key.short)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .card()
    }

    private func note(_ item: Product, _ g: Double) -> String? {
        if g == 0 { return "Pas besoin pour ce repas" }
        var parts: [String] = []
        if let unit = item.unit {
            let count = g / unit.grams
            parts.append("\(NutritionFormat.number(count)) \(unit.label(count: count))")
        }
        if isWeighedRaw(item.name) { parts.append("pesé cru") }
        if item.fixed != nil { parts.append("fixé") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Weight and log

private struct JournalCard: View {
    @Environment(\.modelContext) private var context
    @Environment(NutritionStore.self) private var store
    @Query(sort: \BodyWeightEntry.date) private var entries: [BodyWeightEntry]
    @State private var isAddingWeight = false
    @State private var input: Double?
    @State private var showsLog = false

    var body: some View {
        let weights = NutritionStore.weightsByDay(entries)
        let now = WeightTrend.average(weights, from: 0, to: 6), prev = WeightTrend.average(weights, from: 7, to: 13)
        let trend: Double? = now.count >= 3 && prev.count >= 3 ? (now.avg ?? 0) - (prev.avg ?? 0) : nil
        let losing = NutritionData.goalOffsets[min(max(store.settings.profile.goal, 0), 4)] <= 0
        let log = store.todayLog
        let eaten = store.eaten()

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                NavigationLink {
                    BodyWeightView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        CardTitle("Poids", symbol: "scalemass.fill", tint: .indigo)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(now.avg.map(\.kgText) ?? weights[DayKey.today].map(\.kgText) ?? "—")
                                .font(.display(22))
                                .foregroundStyle(.primary)
                            if let trend {
                                Text((trend > 0 ? "+" : "") + trend.kgText)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle((losing ? trend <= 0 : trend >= 0) ? Color.green : Color.orange)
                            }
                        }
                        Text(now.avg == nil ? "pèse-toi le matin à jeun" : "moyenne sur 7 jours")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 12)
                if weights.count > 1 {
                    sparkline(weights).frame(width: 96, height: 36)
                }
                Button {
                    input = nil
                    isAddingWeight = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .glassButton()
                .buttonBorderShape(.circle)
                .accessibilityLabel("Noter mon poids")
            }

            if let message = adjustmentNote {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            DisclosureGroup(isExpanded: $showsLog) {
                VStack(spacing: 0) {
                    if log.isEmpty {
                        Text("Rien de noté aujourd'hui.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    ForEach(log) { entry in
                        HStack {
                            Text(entry.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("\(Int(entry.kcal.rounded())) kcal · \(Int(entry.g)) g")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .contextMenu {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                withAnimation(.appSpring) { store.todayLog.removeAll { $0.id == entry.id } }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Mangé aujourd'hui").font(.subheadline)
                    Spacer()
                    Text("\(Int(eaten.kcal.rounded())) kcal · \(Int(eaten.p.rounded())) g P")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.secondary)
        }
        .card()
        .alert("Poids du jour", isPresented: $isAddingWeight) {
            TextField("kg", value: $input, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
            Button("Annuler", role: .cancel) {}
            Button("Noter") { save() }
        } message: {
            Text("Le matin à jeun, c'est le plus fiable.")
        }
    }

    private var adjustmentNote: String? {
        let adj = store.settings.adj
        guard let message = adj.message, let last = adj.last, DayKey.daysBetween(last, DayKey.today) < 7 else { return nil }
        return message
    }

    /// Last 30 days, 7-day moving average.
    private func sparkline(_ weights: [String: Double]) -> some View {
        let days = (0..<30).reversed().map { DayKey.offset($0) }
        let points: [ChartPoint] = days.enumerated().compactMap { i, d in
            let window = (0..<7).compactMap { k -> Double? in i - k >= 0 ? weights[days[i - k]] : nil }
            guard !window.isEmpty, let date = DayKey.date(d) else { return nil }
            return ChartPoint(date: date, value: window.reduce(0, +) / Double(window.count))
        }
        return Chart(points) { p in
            LineMark(x: .value("Jour", p.date), y: .value("Poids", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    private func save() {
        guard let kg = input, kg > 20, kg < 400 else { return }
        let today = DayKey.today
        if let existing = entries.last(where: { DayKey.of($0.date) == today }) {
            existing.weight = kg
            existing.date = .now
        } else {
            context.insert(BodyWeightEntry(date: .now, weight: kg))
        }
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? entries
        store.checkAdjustment(entries: all)
    }
}

struct ChartPoint: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

import SwiftUI
import SwiftData
import Charts

struct TodayPage: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DaySummaryCard()
            SlotPicker()
            if let doses = session.doses, doses.count == store.state.cart.count {
                DosesSection(doses: doses)
            } else {
                MealBuilder()
            }
            WeightCard()
            TodayLog()
        }
    }
}

// MARK: - Day summary

private struct DaySummaryCard: View {
    @Environment(NutritionStore.self) private var store

    var body: some View {
        let t = store.settings.dayTargets, e = store.eaten()
        let left = Int((t.kcal - e.kcal).rounded())
        let protLeft = max(0, Int((t.p - e.p).rounded()))
        let evening = Calendar.current.component(.hour, from: .now) >= 18
        let alert = evening && protLeft > 40

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: t.kcal > 0 ? e.kcal / t.kcal : 0, tint: left < 0 ? .red : Theme.calories, lineWidth: 16)
                    VStack(spacing: 0) {
                        Text("\(abs(left))")
                            .font(.title.bold())
                            .fontDesign(.rounded)
                            .contentTransition(.numericText())
                        Text(left >= 0 ? "kcal restantes" : "kcal en trop")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 118, height: 118)

                VStack(spacing: 12) {
                    ForEach([MacroKey.p, .c, .f]) { key in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(key.label).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(e[key].rounded())) / \(Int(t[key])) g")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressBar(progress: t[key] > 0 ? e[key] / t[key] : 0, tint: key.color)
                        }
                    }
                }
            }

            Label {
                Text(protLeft == 0
                     ? "Objectif protéines atteint."
                     : alert
                     ? "Il te manque \(protLeft) g de protéines ce soir : un skyr (≈ 15 g par pot), du blanc de poulet (≈ 31 g pour 100 g) ou une dose de whey (≈ 24 g)."
                     : "Encore \(protLeft) g de protéines à manger aujourd'hui.")
            } icon: {
                Image(systemName: protLeft == 0 ? "checkmark.seal.fill" : alert ? "exclamationmark.circle.fill" : "bolt.heart.fill")
                    .foregroundStyle(protLeft == 0 ? Color.green : alert ? Color.orange : Theme.protein)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .card()
    }
}

// MARK: - Meal slot

private struct SlotPicker: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session

    var body: some View {
        let slots = store.settings.slotTargets
        let selected = slots.first { $0.id == session.slotId } ?? slots.first

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Quel repas ?")
            HStack(spacing: 8) {
                ForEach(slots) { slot in
                    let isOn = slot.id == selected?.id
                    Button {
                        withAnimation(.snappy) {
                            session.slotId = slot.id
                            if session.doses != nil {
                                session.doses = PortionSolver.solve(store.state.cart, target: store.remaining(for: slot.id))
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: slot.type.symbol).font(.subheadline)
                            Text(slot.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text("\(Int(store.remaining(for: slot.id).kcal)) kcal")
                                .font(.caption2)
                                .monospacedDigit()
                                .opacity(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Theme.card),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }

            if let selected {
                let rem = store.remaining(for: selected.id)
                let done = store.eaten(slot: selected.id).kcal
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ForEach(MacroKey.allCases) { key in
                            MacroGauge(key: key, value: rem[key], total: selected.target[key])
                        }
                    }
                    Text(done > 0
                         ? "Il te reste ça pour \(selected.label.lowercased()) (déjà \(Int(done)) kcal notées sur ce créneau)."
                         : "Ton objectif pour \(selected.label.lowercased()).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .card()
            }
        }
    }
}

// MARK: - Building the meal

private struct MealBuilder: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Ce que tu manges") {
                if !store.state.cart.isEmpty {
                    Text("\(store.state.cart.count) produit\(store.state.cart.count > 1 ? "s" : "")")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = session.mealError { InlineError(text: error) }

            VStack(spacing: 0) {
                if store.state.cart.isEmpty {
                    EmptyCardContent(
                        symbol: "barcode.viewfinder",
                        title: "Qu'est-ce qu'on mange ?",
                        message: "Scanne chaque produit, ou touche un aliment ci-dessous. Quand tout y est, appuie sur Calculer."
                    )
                } else {
                    ForEach(Array(store.state.cart.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 60) }
                        CartRow(index: index)
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("Sans code-barres ? Touche un aliment (poids cru)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(quickFoods) { food in
                        Button {
                            withAnimation(.snappy) {
                                session.doses = nil
                                store.addToCart(Product(food: food))
                            }
                            session.flash("\(food.shortName) ajouté · note \(store.settings.score(food).grade.rawValue)")
                        } label: {
                            Label(food.shortName, systemImage: "plus")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.field, in: Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
                HStack {
                    TextField("Code-barres à la main", text: $code)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Ajouter") {
                        let value = code
                        code = ""
                        hideKeyboard()
                        Task { await session.lookup(value, for: .meal, store: store) }
                    }
                    .glassButton()
                    .disabled(code.isEmpty || session.isLookingUp)
                }
            }
            .card()
        }
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

    var body: some View {
        @Bindable var store = store
        if index < store.state.cart.count {
            let item = store.state.cart[index]
            HStack(alignment: .top, spacing: 12) {
                ProductThumb(product: item, grade: store.settings.score(item).grade)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.body.weight(.semibold)).lineLimit(2)
                    MacroMixBar(n: item.n)
                    Text(NutritionFormat.macroLine(item.n))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { item.fixed != nil },
                            set: { on in
                                session.doses = nil
                                store.state.cart[index].fixed = on ? (item.unit?.grams ?? 100) : nil
                            }
                        )) {
                            Text("Quantité fixe").font(.caption.weight(.semibold))
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        if item.fixed != nil {
                            TextField("g", value: $store.state.cart[index].fixed, format: .number)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .font(.caption)
                            Text("g").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) {
                        session.doses = nil
                        _ = store.state.cart.remove(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retirer \(item.name)")
            }
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Result

private struct DosesSection: View {
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
            SectionHeader("Tes doses à peser")
            VStack(spacing: 0) {
                ForEach(Array(cart.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Divider().padding(.leading, 60) }
                    let g = doses[i]
                    HStack(spacing: 12) {
                        ProductThumb(product: item, grade: store.settings.score(item).grade)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.body.weight(.semibold)).lineLimit(2)
                            Text("\(Int((item.n.kcal * g / 100).rounded())) kcal · \(NutritionFormat.number(item.n.p * g / 100)) g de protéines")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let note = note(item, g) {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(g))")
                                .font(.title.bold())
                                .fontDesign(.rounded)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("g").font(.headline).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(g == 0 ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : AnyShapeStyle(Color.accentColor))
                    }
                    .padding(.vertical, 10)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Label(onTarget ? "Repas pile dans tes objectifs"
                      : worst.1 < 0 ? "Il manque des \(worst.0.label.lowercased()) : ajoute un produit qui en contient plus"
                      : "Trop de \(worst.0.label.lowercased()) : retire un produit ou fixe sa quantité plus bas",
                      systemImage: onTarget ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(onTarget ? Color.green : Color.orange)
                ForEach(MacroKey.allCases) { key in
                    HStack(spacing: 10) {
                        Text(key.label).font(.subheadline).frame(width: 80, alignment: .leading)
                        ProgressBar(progress: target[key] > 0 ? total[key] / target[key] : 0, tint: key.color)
                        Text("\(Int(total[key].rounded())) / \(Int(target[key].rounded()))\(key == .kcal ? "" : " g")")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 86, alignment: .trailing)
                    }
                }
            }
            .card()
        }
    }

    private func note(_ item: Product, _ g: Double) -> String? {
        if g == 0 { return "Pas besoin : le reste du repas couvre déjà tout" }
        var parts: [String] = []
        if let unit = item.unit {
            let count = g / unit.grams
            parts.append("\(NutritionFormat.number(count)) \(unit.label(count: count))")
        }
        if isWeighedRaw(item.name) { parts.append("pesé cru / sec") }
        if item.fixed != nil { parts.append("quantité fixe") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Weight

private struct WeightCard: View {
    @Environment(\.modelContext) private var context
    @Environment(NutritionStore.self) private var store
    @Query(sort: \BodyWeightEntry.date) private var entries: [BodyWeightEntry]
    @State private var input: Double?

    var body: some View {
        let weights = NutritionStore.weightsByDay(entries)
        let now = WeightTrend.average(weights, from: 0, to: 6), prev = WeightTrend.average(weights, from: 7, to: 13)
        let trend: Double? = now.count >= 3 && prev.count >= 3 ? (now.avg ?? 0) - (prev.avg ?? 0) : nil
        let losing = NutritionData.goalOffsets[min(max(store.settings.profile.goal, 0), 4)] <= 0

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Mon poids") {
                NavigationLink("Historique") { BodyWeightView() }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    stat(weights[DayKey.today].map(\.kgText) ?? "—", "Aujourd'hui")
                    stat(now.avg.map(\.kgText) ?? "—", "Moy. 7 jours")
                    stat(trend.map { ($0 > 0 ? "+" : "") + $0.kgText } ?? "—", "Sur 7 jours",
                         tint: trend.map { (losing ? $0 <= 0 : $0 >= 0) ? Color.green : Color.orange })
                }

                if weights.count > 1 { chart(weights) }

                if let note = note(weights, now: now.count, prev: prev.count) {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Poids du jour (kg)", value: $input, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Noter") { save() }
                        .glassProminentButton()
                        .disabled(!((input ?? 0) > 20 && (input ?? 0) < 400))
                }
            }
            .card()
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .fontDesign(.rounded)
                .foregroundStyle(tint ?? Color.primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Last 30 days: dots for weigh-ins, line for the 7-day moving average.
    private func chart(_ weights: [String: Double]) -> some View {
        let days = (0..<30).reversed().map { DayKey.offset($0) }
        let points = days.compactMap { d in weights[d].map { ChartPoint(date: DayKey.date(d) ?? .now, value: $0) } }
        let average: [ChartPoint] = days.enumerated().compactMap { i, d in
            let window = (0..<7).compactMap { k -> Double? in
                let j = i - k
                return j >= 0 ? weights[days[j]] : nil
            }
            guard !window.isEmpty, let date = DayKey.date(d) else { return nil }
            return ChartPoint(date: date, value: window.reduce(0, +) / Double(window.count))
        }
        return Chart {
            ForEach(average) { p in
                LineMark(x: .value("Jour", p.date), y: .value("Moyenne", p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(points) { p in
                PointMark(x: .value("Jour", p.date), y: .value("Poids", p.value))
                    .foregroundStyle(.secondary)
                    .symbolSize(18)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .frame(height: 120)
    }

    private func note(_ weights: [String: Double], now: Int, prev: Int) -> String? {
        if weights.isEmpty {
            return "Pèse-toi le matin à jeun. Note-le chaque jour : je fais la moyenne sur 7 jours pour lisser l'eau et le sel."
        }
        let adj = store.settings.adj
        if let message = adj.message, let last = adj.last {
            let days = DayKey.daysBetween(last, DayKey.today)
            if days < 7 {
                let wait = 7 - days
                return message + (wait > 0 && wait < 7 ? " Prochain bilan dans \(wait) jour\(wait > 1 ? "s" : "")." : "")
            }
        }
        if now < 3 || prev < 3 {
            let n = max(1, max(0, 3 - now) + max(0, 3 - prev))
            return "Encore \(n) pesée\(n > 1 ? "s" : "") et je pourrai juger ta tendance."
        }
        return nil
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
        input = nil
        hideKeyboard()
        let all = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? entries
        store.checkAdjustment(entries: all)
    }
}

// MARK: - Today's log

private struct TodayLog: View {
    @Environment(NutritionStore.self) private var store
    @State private var isExpanded = false

    var body: some View {
        let log = store.todayLog
        let total = store.eaten()
        let slots = store.settings.slotTargets

        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 0) {
                if log.isEmpty {
                    Text("Rien de noté aujourd'hui.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                ForEach(log) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline.weight(.semibold))
                            Text("\(slots.first { $0.id == entry.slot }?.name ?? "") · \(Int(entry.kcal.rounded())) kcal · P \(NutritionFormat.number(entry.p))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(entry.g)) g")
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.rounded)
                        Button {
                            withAnimation { store.todayLog.removeAll { $0.id == entry.id } }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retirer \(entry.name)")
                    }
                    .padding(.vertical, 8)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mangé aujourd'hui").font(.headline)
                Text("\(Int(total.kcal.rounded())) kcal · \(Int(total.p.rounded())) g de protéines")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
        .card()
    }
}

struct ChartPoint: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

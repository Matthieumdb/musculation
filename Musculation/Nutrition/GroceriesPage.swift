import SwiftUI

struct GroceriesPage: View {
    @Environment(NutritionSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if session.groceryItem != nil {
                ScannedProductSection()
            } else {
                ScanIntro()
            }
            ShoppingListSection()
            GoodChoicesSection()
        }
    }
}

// MARK: - Scan

private struct ScanIntro: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EmptyCardContent(
                symbol: "cart.fill",
                title: "Scanne un produit en magasin",
                message: "Je te dis s'il est bon pour toi et combien en prendre pour la semaine, en tenant compte des autres produits du même rayon."
            )
            if let error = session.groceryError { InlineError(text: error) }
            HStack {
                TextField("Code-barres à la main", text: $code)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Chercher") {
                    let value = code
                    code = ""
                    hideKeyboard()
                    Task { await session.lookup(value, for: .groceries, store: store) }
                }
                .glassButton()
                .disabled(code.isEmpty || session.isLookingUp)
            }
        }
        .card()
    }
}

private struct ScannedProductSection: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    @State private var takeGrams: Double?
    @State private var packPrice: Double?

    var body: some View {
        if let product = session.groceryItem {
            let settings = store.settings
            let score = settings.score(product)
            let grade = score.grade
            let quantity = settings.weeklyQuantity(product, aisle: product.fam, variety: store.state.variety)
            let excluded = score.excludedBy != nil
            let row = !excluded ? session.groceryMatch.flatMap { store.state.shopList.indices.contains($0) ? $0 : nil } : nil

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Produit scanné") {
                    Button("Fermer") { close() }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ProductThumb(product: product, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.headline)
                            Text([product.brand, product.packG > 0 ? NutritionFormat.weight(product.packG) : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 16) {
                        ZStack {
                            ProgressRing(progress: Double(score.value) / 100, tint: grade.color, lineWidth: 8)
                            VStack(spacing: 0) {
                                Text(grade.rawValue).font(.title2.bold()).fontDesign(.rounded).foregroundStyle(grade.color)
                                Text("\(score.value)/100").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(grade.verdict).font(.headline).foregroundStyle(grade.color)
                            Text(NutritionFormat.macroLine(product.n)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !score.reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(score.reasons, id: \.self) { reason in
                                Label(reason.text, systemImage: reason.bad ? "minus.circle.fill" : "plus.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(reason.bad ? Color.orange : Color.green)
                            }
                        }
                    }
                }
                .card()

                if !excluded && !openRows.isEmpty {
                    Picker("C'est pour", selection: Binding(
                        get: { session.groceryMatch ?? -1 },
                        set: { session.groceryMatch = $0 < 0 ? nil : $0; session.groceryTake = nil }
                    )) {
                        Text("Rien de ma liste").tag(-1)
                        ForEach(openRows, id: \.self) { i in
                            let r = store.state.shopList[i]
                            Text("\(r.title) · \(NutritionFormat.weight(settings.need(r, variety: store.state.variety)))").tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                    .card()
                }

                if let row {
                    listMatch(product: product, rowIndex: row)
                } else {
                    planCard(product: product, quantity: quantity, excluded: excluded)
                }
            }
        }
    }

    private var openRows: [Int] {
        store.state.shopList.indices.filter { !store.state.shopList[$0].done || $0 == session.groceryMatch }
    }

    private func close() {
        withAnimation(.snappy) {
            session.groceryItem = nil
            session.groceryMatch = nil
            session.groceryTake = nil
        }
    }

    @ViewBuilder
    private func planCard(product: Product, quantity: WeeklyQuantity, excluded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Menu {
                Picker("Rayon", selection: Binding(
                    get: { product.fam },
                    set: { session.groceryItem?.fam = $0 }
                )) {
                    ForEach(Aisle.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                HStack {
                    Label(product.fam.label, systemImage: product.fam.symbol)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .font(.subheadline.weight(.semibold))
            }

            VStack(spacing: 2) {
                Text(excluded ? "0 g" : product.fam == .extras ? (quantity.grams > 0 ? "≤ \(NutritionFormat.weight(quantity.grams))" : "0 g") : NutritionFormat.weight(quantity.grams))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(excluded ? "tu as exclu ce type de produit dans tes réglages"
                     : product.fam == .extras ? "maximum pour la semaine"
                     : "pour la semaine\(isWeighedRaw(product.name) ? " · poids cru" : "")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !excluded && product.fam != .extras, let packs = NutritionFormat.packs(quantity.grams, packG: product.packG) {
                    Text(packs).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            if product.fam != .extras && !excluded {
                CountStepper(
                    title: "Produits différents en \(product.fam.label.lowercased()) cette semaine",
                    value: Binding(
                        get: { quantity.count },
                        set: { store.state.variety[product.fam] = min(8, max(1, $0)) }
                    ),
                    range: 1...8
                )
                .font(.subheadline)
            }
            if !excluded {
                Text(quantity.explanation).font(.footnote).foregroundStyle(.secondary)
                Button {
                    store.addToList(product, aisle: product.fam)
                    session.flash("\(product.name) : \(NutritionFormat.weight(quantity.grams)) ajouté à ta liste")
                    close()
                } label: {
                    Label("Ajouter à ma liste", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .glassProminentButton()
                .controlSize(.large)
            }
        }
        .card()
    }

    @ViewBuilder
    private func listMatch(product: Product, rowIndex: Int) -> some View {
        let row = store.state.shopList[rowIndex]
        let need = store.settings.need(row, variety: store.state.variety)
        let left = max(0, need - row.got)
        let takeCount = session.groceryTake ?? (product.packG > 0 ? max(1, Int((left / product.packG).rounded(.up))) : Int(left.rounded()))

        VStack(alignment: .leading, spacing: 14) {
            Text("Sur ta liste de courses").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Text(left > 0 ? NutritionFormat.weight(left) : "✓")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("\(left > 0 ? "encore à prendre" : "Tu as déjà tout ce qu'il faut") · il en faut \(NutritionFormat.weight(need)), \(NutritionFormat.weight(row.got)) déjà dans le caddie")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if left > 0, let packs = NutritionFormat.packs(left, packG: product.packG) {
                    Text(packs).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            if product.packG > 0 {
                CountStepper(
                    title: "Je prends (paquets de \(NutritionFormat.weight(product.packG)))",
                    value: Binding(get: { takeCount }, set: { session.groceryTake = max(1, $0) }),
                    range: 1...30
                )
                TextField("Prix du paquet (facultatif, \(store.settings.currency))", value: $packPrice, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            } else {
                HStack {
                    Text("Je prends (g)")
                    Spacer()
                    TextField("g", value: Binding(get: { takeGrams ?? Double(takeCount) }, set: { takeGrams = $0 }), format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .multilineTextAlignment(.center)
                }
            }

            Button {
                take(product: product, rowIndex: rowIndex, count: takeCount)
            } label: {
                Label("Mettre dans le caddie", systemImage: "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .glassProminentButton()
            .controlSize(.large)
        }
        .card()
    }

    private func take(product: Product, rowIndex: Int, count: Int) {
        guard store.state.shopList.indices.contains(rowIndex) else { return }
        var row = store.state.shopList[rowIndex]
        let g = product.packG > 0 ? Double(count) * product.packG : (takeGrams ?? Double(count))
        row.got += g
        if product.packG > 0 { row.ref?.packG = product.packG }
        if let price = packPrice, price > 0, product.packG > 0 { row.ppk = price / (product.packG / 1000) }
        let need = store.settings.need(row, variety: store.state.variety)
        row.done = row.got >= need * 0.95
        store.state.shopList[rowIndex] = row
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        session.flash(row.done ? "\(row.title) : quantité atteinte, rayé de ta liste" : "\(row.title) : encore \(NutritionFormat.weight(need - row.got)) à prendre")
        takeGrams = nil
        packPrice = nil
        close()
    }
}

// MARK: - List

private struct ShoppingListSection: View {
    @Environment(NutritionStore.self) private var store
    @State private var isConfirmingClear = false

    var body: some View {
        let list = store.state.shopList
        let settings = store.settings
        let variety = store.state.variety
        let total = list.reduce(0) { $0 + settings.pricePerKg($1) * settings.need($1, variety: variety) / 1000 }
        let left = list.reduce(0) { $0 + ($1.done ? 0 : settings.pricePerKg($1) * max(0, settings.need($1, variety: variety) - $1.got) / 1000) }
        // What is left to take first, crossed-off rows at the bottom
        let order = list.indices.sorted { (list[$0].done ? 1 : 0, $0) < (list[$1].done ? 1 : 0, $1) }

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Ma liste de la semaine") {
                if !list.isEmpty {
                    Text("\(list.filter(\.done).count)/\(list.count) dans le caddie").foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                if list.isEmpty {
                    EmptyCardContent(symbol: "list.bullet.clipboard", title: "Liste vide",
                                     message: "Scanne un produit ou pioche dans les bons choix ci-dessous.")
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estimation de la liste").font(.subheadline.weight(.semibold))
                            Text("reste ≈ \(NutritionFormat.money(left, currency: settings.currency))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("≈ \(NutritionFormat.money(total, currency: settings.currency))")
                            .font(.title3.bold())
                            .fontDesign(.rounded)
                    }
                    .padding(.bottom, 10)
                    ForEach(order, id: \.self) { i in
                        Divider()
                        ShopRowView(index: i)
                    }
                    Divider()
                    Button("Vider la liste", role: .destructive) { isConfirmingClear = true }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                }
            }
            .card()
        }
        .confirmationDialog("Vider la liste de courses ?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Vider", role: .destructive) { withAnimation { store.state.shopList = [] } }
        }
    }
}

private struct ShopRowView: View {
    @Environment(NutritionStore.self) private var store
    let index: Int

    var body: some View {
        if store.state.shopList.indices.contains(index) {
            let row = store.state.shopList[index]
            let settings = store.settings
            let need = settings.need(row, variety: store.state.variety)
            let left = max(0, need - row.got)
            let packs = row.fam == .extras || row.ref == nil || row.done ? nil : NutritionFormat.packs(row.got > 0 ? left : need, packG: row.ref?.packG ?? 0)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { store.state.shopList[index].done.toggle() }
                } label: {
                    Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(row.done ? Color.accentColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.done ? "Décocher" : "Cocher")

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.body)
                        .strikethrough(row.done)
                        .foregroundStyle(row.done ? Color.secondary : Color.primary)
                    Text(([row.fam.label, "≈ \(NutritionFormat.money(settings.pricePerKg(row) * need / 1000, currency: settings.currency))"]
                          + [packs, row.got > 0 && !row.done ? "\(NutritionFormat.weight(left)) encore à prendre" : nil].compactMap { $0 })
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if row.got > 0 && !row.done {
                        ProgressBar(progress: need > 0 ? row.got / need : 0, tint: .accentColor, height: 4)
                    }
                }
                Spacer(minLength: 0)
                Text("\(row.fam == .extras ? "≤ " : "")\(row.got > 0 && !row.done ? NutritionFormat.weight(row.got) + " / " : "")\(NutritionFormat.weight(need))")
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(row.done ? Color.secondary : Color.primary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    withAnimation { _ = store.state.shopList.remove(at: index) }
                }
            }
        }
    }
}

// MARK: - Good choices

private struct GoodChoicesSection: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    @State private var expanded: Set<Aisle> = [.viandes]

    private let order: [Aisle] = [.viandes, .oeufs, .laitiers, .feculents, .legumes, .fruits, .fromages, .graisses, .sauces, .poudre]

    var body: some View {
        let settings = store.settings
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Bons choix pour toi")
            Text("Les aliments qui collent à ton objectif, rayon par rayon, avec la quantité à prévoir pour la semaine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(order) { aisle in
                    let foods = NutritionData.foods
                        .filter { $0.fam == aisle && settings.allowed($0) }
                        .map { ScoredFood(food: $0, score: settings.score($0).value) }
                        .sorted { (settings.pref($0.food), $0.score) > (settings.pref($1.food), $1.score) }
                    if !foods.isEmpty {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expanded.contains(aisle) },
                            set: { if $0 { expanded.insert(aisle) } else { expanded.remove(aisle) } }
                        )) {
                            VStack(spacing: 0) {
                                ForEach(foods) { item in
                                    idea(item.food, score: item.score)
                                }
                            }
                        } label: {
                            Label(aisle.label, systemImage: aisle.symbol)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .tint(.secondary)
                        .padding(.vertical, 8)
                        if aisle != order.last { Divider() }
                    }
                }
            }
            .card()
        }
    }

    private func idea(_ food: Food, score: Int) -> some View {
        let settings = store.settings
        let product = Product(food: food)
        let grams = settings.weeklyQuantity(product, aisle: food.fam, variety: store.state.variety).grams
        return HStack(spacing: 10) {
            GradeBadge(grade: Grade(score))
            Text(food.name).font(.subheadline)
            if settings.pref(food) == 1 {
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
            }
            Spacer()
            Text("\(NutritionFormat.weight(grams))/sem.")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                store.addToList(product, aisle: food.fam)
                session.flash("\(food.name) : \(NutritionFormat.weight(grams)) ajouté à ta liste")
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Ajouter \(food.name) à ma liste")
        }
        .padding(.vertical, 6)
    }
}

private struct ScoredFood: Identifiable {
    var food: Food
    var score: Int
    var id: String { food.id }
}

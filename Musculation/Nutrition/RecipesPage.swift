import SwiftUI

struct RecipesPage: View {
    @Environment(NutritionStore.self) private var store

    var body: some View {
        let groups = store.state.recipeGroups ?? []
        let count = groups.reduce(0) { $0 + $1.items.count }

        VStack(alignment: .leading, spacing: 16) {
            RecipeSetup()
            if count == 0 {
                EmptyCardContent(
                    symbol: "frying.pan.fill",
                    title: store.state.recipeGroups == nil ? "Pas encore de recettes" : "Aucune recette pour ces styles",
                    message: store.state.recipeGroups == nil
                        ? "Choisis combien de recettes, puis appuie sur Proposer."
                        : "Retire un style ou change de repas, puis relance."
                )
                .card()
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.id) { gi, group in
                    if !group.items.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Label(group.type.label, systemImage: group.type.symbol)
                                .font(.display(20, relativeTo: .title3))
                                .padding(.bottom, 4)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, _ in
                                Divider()
                                RecipeCard(group: gi, index: index)
                            }
                        }
                        .card()
                    }
                }
                RecipeWeek()
            }
        }
    }
}

// MARK: - Setup

private struct RecipeSetup: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session

    var body: some View {
        let counts = store.recipeCounts
        let total = counts.values.reduce(0, +)
        let styles = store.state.recipeStyles

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(MealType.allCases) { type in
                    MiniCounter(title: type.label, symbol: type.symbol, value: Binding(
                        get: { counts[type] ?? 0 },
                        set: { value in
                            var c = store.recipeCounts
                            c[type] = min(14, max(0, value))
                            store.state.recipeCounts = c
                        }
                    ))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChoiceChip(title: "Tout", isOn: styles.isEmpty) { store.state.recipeStyles = [] }
                    ForEach(RecipeStyle.allCases) { style in
                        ChoiceChip(title: style.label, isOn: styles.contains(style.rawValue)) {
                            if styles.contains(style.rawValue) {
                                store.state.recipeStyles.removeAll { $0 == style.rawValue }
                            } else {
                                store.state.recipeStyles.append(style.rawValue)
                            }
                        }
                    }
                    ForEach(Array(store.state.favorites.enumerated()), id: \.offset) { _, fav in
                        if let tpl = NutritionData.recipe(fav.tpl) {
                            ChoiceChip(title: tpl.name, symbol: "star.fill", isOn: false) { addFavorite(fav, name: tpl.name) }
                        }
                    }
                }
            }

            Button {
                withAnimation(.appSpring) {
                    session.editingRecipe = nil
                    store.newRecipes()
                }
            } label: {
                Label("Proposer \(total) recette\(total > 1 ? "s" : "")", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .glassProminentButton()
            .controlSize(.large)
            .disabled(total == 0)
        }
        .card()
    }

    private func addFavorite(_ fav: FavoriteRecipe, name: String) {
        var groups = store.state.recipeGroups ?? []
        if let i = groups.firstIndex(where: { $0.type == fav.type }) {
            groups[i].items.append(RecipePick(tpl: fav.tpl, picks: fav.picks))
        } else {
            groups.append(RecipeGroup(type: fav.type, items: [RecipePick(tpl: fav.tpl, picks: fav.picks)]))
            groups.sort { MealType.allCases.firstIndex(of: $0.type)! < MealType.allCases.firstIndex(of: $1.type)! }
        }
        var c = store.recipeCounts
        c[fav.type] = groups.first { $0.type == fav.type }?.items.count
        withAnimation(.appSpring) {
            store.state.recipeCounts = c
            store.state.recipeGroups = groups
        }
        session.flash("\(name) ajouté à ta sélection")
    }
}

// MARK: - Card

private struct RecipeCard: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    let group: Int
    let index: Int
    @State private var isOpen = false

    var body: some View {
        if let groups = store.state.recipeGroups, groups.indices.contains(group), groups[group].items.indices.contains(index) {
            let g = groups[group]
            let pick = g.items[index]
            let settings = store.settings
            if let built = settings.build(pick, target: settings.typeTarget(g.type)) {
                let key = NutritionStore.recipeKey(group, index)
                let editing = session.editingRecipe == key
                let isFavorite = store.state.favorites.contains { $0.tpl == pick.tpl }

                let open = isOpen || editing

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.appEase) { isOpen.toggle() }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(built.template.name).font(.headline).multilineTextAlignment(.leading)
                                        if isFavorite {
                                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                        }
                                    }
                                    Text("\(built.template.minutes) min · \(Int(built.totals.kcal.rounded())) kcal · \(Int(built.totals.p.rounded())) g prot.\(pick.servings > 1 ? " · ×\(pick.servings)" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(open ? 180 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("Changer de recette", systemImage: "arrow.triangle.2.circlepath") { change() }
                            Button(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: isFavorite ? "star.slash" : "star") {
                                toggleFavorite(pick, type: g.type, isFavorite: isFavorite)
                            }
                            Button("Supprimer", systemImage: "trash", role: .destructive) { delete() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Options")
                    }

                    if open {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 6) {
                                ForEach(built.template.tags, id: \.self) { tag in
                                    if let style = RecipeStyle(rawValue: tag) {
                                        Text(style.label)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .foregroundStyle(Color.accentColor)
                                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    }
                                }
                            }

                            HStack(spacing: 14) {
                                macro("\(Int(built.totals.kcal.rounded()))", "kcal", Theme.calories)
                                macro("\(Int(built.totals.p.rounded())) g", "Prot.", Theme.protein)
                                macro("\(Int(built.totals.c.rounded())) g", "Gluc.", Theme.carbs)
                                macro("\(Int(built.totals.f.rounded())) g", "Lip.", Theme.fat)
                            }

                            VStack(spacing: 8) {
                                ForEach(built.items.filter { $0.grams > 0 || editing }) { item in
                                    ingredient(item, built: built, editing: editing)
                                }
                            }

                            if pick.servings > 1 {
                                Text("Quantités pour 1 portion · à faire \(pick.servings) fois (les courses comptent les \(pick.servings)).")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Text(built.steps)
                                .font(.subheadline)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Stepper(value: Binding(
                                get: { pick.servings },
                                set: { value in store.state.recipeGroups?[group].items[index].servings = min(14, max(1, value)) }
                            ), in: 1...14) {
                                Text("Portions : \(pick.servings)").font(.subheadline.weight(.semibold))
                            }

                            HStack(spacing: 10) {
                                Button(editing ? "Terminé" : "Modifier") {
                                    withAnimation(.appSpring) { session.editingRecipe = editing ? nil : key }
                                }
                                .glassButton()

                                Button {
                                    cook(built, type: g.type)
                                } label: {
                                    Label("Je cuisine ça", systemImage: "frying.pan")
                                        .frame(maxWidth: .infinity)
                                }
                                .glassProminentButton()
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func macro(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.bold()).fontDesign(.rounded).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func ingredient(_ item: RecipeIngredient, built: BuiltRecipe, editing: Bool) -> some View {
        let settings = store.settings
        let choices = settings.choices(for: built.template.parts[item.part])
        HStack(spacing: 10) {
            GradeBadge(grade: settings.score(item.food).grade, size: 20)
            if editing && choices.count > 1 {
                Picker("Changer d'ingrédient", selection: Binding(
                    get: { item.food.id },
                    set: { id in
                        var picks = built.picks
                        picks[item.part] = id
                        store.state.recipeGroups?[group].items[index].picks = picks
                    }
                )) {
                    ForEach(choices) { food in
                        Text(food.name + (settings.pref(food) == 1 ? " ♥" : "")).tag(food.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            } else {
                Text(item.food.name).font(.subheadline)
                if settings.pref(item.food) == 1 {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(item.grams)) g").font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                if let unit = item.food.unit, item.grams > 0 {
                    let n = item.grams / unit.grams
                    Text("\(NutritionFormat.number(n)) \(unit.label(count: n))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func change() {
        guard var groups = store.state.recipeGroups else { return }
        let g = groups[group]
        if var fresh = store.drawRecipes(1, type: g.type, avoid: g.items.map(\.tpl)).first {
            fresh.servings = g.items[index].servings
            groups[group].items[index] = fresh
            withAnimation(.appSpring) {
                store.state.recipeGroups = groups
                session.editingRecipe = nil
            }
        }
    }

    private func toggleFavorite(_ pick: RecipePick, type: MealType, isFavorite: Bool) {
        if isFavorite {
            store.state.favorites.removeAll { $0.tpl == pick.tpl }
        } else {
            store.state.favorites.append(FavoriteRecipe(tpl: pick.tpl, picks: pick.picks, type: type))
        }
    }

    private func delete() {
        guard var groups = store.state.recipeGroups else { return }
        groups[group].items.remove(at: index)
        var c = store.recipeCounts
        c[groups[group].type] = groups[group].items.count
        withAnimation(.appSpring) {
            store.state.planOverrides = [:]
            store.state.recipeCounts = c
            store.state.recipeGroups = groups
            session.editingRecipe = nil
        }
    }

    /// Sends the recipe to the meal tab with its quantities fixed.
    private func cook(_ built: BuiltRecipe, type: MealType) {
        let settings = store.settings
        store.state.cart = built.items.filter { $0.grams > 0 }.map { item in
            var p = Product(food: item.food)
            p.fixed = item.grams
            return p
        }
        let same = settings.slotTargets.filter { $0.type == type }
        let guess = settings.guessSlot()
        session.slotId = (same.first { $0.id == guess } ?? same.first)?.id ?? session.slotId
        session.doses = PortionSolver.solve(store.state.cart, target: store.remaining(for: session.slotId))
        withAnimation(.appSpring) { session.page = .today }
    }
}

// MARK: - Groceries and plan

/// Grocery totals and the week plan, folded into one card.
private struct RecipeWeek: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session
    @State private var showsGroceries = false
    @State private var showsPlan = false

    var body: some View {
        let totals = store.recipeTotals()
        let servings = (store.state.recipeGroups ?? []).reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.servings } }
        let plan = store.plan()
        let groups = store.state.recipeGroups ?? []

        VStack(alignment: .leading, spacing: 0) {
            Text("Courses et semaine").font(.display(20, relativeTo: .title3))
            Text("\(servings) portion\(servings > 1 ? "s" : "") · \(totals.count) produit\(totals.count > 1 ? "s" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            Divider()
            DisclosureGroup(isExpanded: $showsGroceries) {
                VStack(spacing: 8) {
                    ForEach(totals) { t in
                        HStack(spacing: 10) {
                            GradeBadge(grade: store.settings.score(t.food).grade, size: 20)
                            Text(t.food.name).font(.subheadline)
                            if t.recipes > 1 {
                                Text("×\(t.recipes)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(NutritionFormat.weight(t.grams)).font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Ingrédients à acheter", systemImage: "basket")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
            .padding(.vertical, 10)

            Divider()
            DisclosureGroup(isExpanded: $showsPlan) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(plan.days) { day in
                        Text(dayName(day))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(day.offset == 0 ? Color.accentColor : Color.secondary)
                            .padding(.top, 10)
                        ForEach(day.cells) { cell in
                            Picker(selection: Binding(
                                get: { cell.key },
                                set: { store.state.planOverrides[cell.id] = $0 }
                            )) {
                                Text("Libre").tag("")
                                ForEach(options(for: cell.slot.type, groups: groups)) { option in
                                    Text(option.name).tag(option.key)
                                }
                            } label: {
                                Text(cell.slot.label)
                            }
                            .pickerStyle(.menu)
                            .font(.subheadline)
                        }
                    }
                    if plan.extra > 0 {
                        Label("\(plan.extra) portion\(plan.extra > 1 ? "s" : "") en trop pour la semaine.", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.top, 10)
                    }
                    if !store.state.planOverrides.isEmpty {
                        Button("Répartir automatiquement") { store.state.planOverrides = [:] }
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 10)
                    }
                }
            } label: {
                Label("Ma semaine", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .tint(.secondary)
            .padding(.vertical, 10)

            Button {
                let n = store.sendRecipesToList()
                withAnimation(.appSpring) { session.page = .groceries }
                session.flash("\(n) produits envoyés à ta liste de courses")
            } label: {
                Label("Tout envoyer à ma liste", systemImage: "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .glassProminentButton()
            .controlSize(.large)
            .padding(.top, 6)
        }
        .card()
    }

    private struct Option: Identifiable {
        var key: String
        var name: String
        var id: String { key }
    }

    private func options(for type: MealType, groups: [RecipeGroup]) -> [Option] {
        groups.enumerated().flatMap { gi, g -> [Option] in
            guard g.type == type else { return [] }
            return g.items.enumerated().map { Option(key: NutritionStore.recipeKey(gi, $0.offset), name: NutritionData.recipe($0.element.tpl)?.name ?? "") }
        }
    }

    private func dayName(_ day: NutritionStore.PlanDay) -> String {
        switch day.offset {
        case 0: "Aujourd'hui"
        case 1: "Demain"
        default: day.date.formatted(.dateTime.weekday(.wide)).capitalized
        }
    }
}

/// Compact − n + counter, three of them fit on one line.
private struct MiniCounter: View {
    let title: String
    let symbol: String
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(spacing: 10) {
                Button { value -= 1 } label: { Image(systemName: "minus") }
                    .disabled(value <= 0)
                Text("\(value)")
                    .font(.display(20))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 24)
                Button { value += 1 } label: { Image(systemName: "plus") }
                    .disabled(value >= 14)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(14, value + 1)
            case .decrement: value = max(0, value - 1)
            @unknown default: break
            }
        }
    }
}

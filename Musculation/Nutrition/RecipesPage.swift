import SwiftUI

struct RecipesPage: View {
    @Environment(NutritionStore.self) private var store

    var body: some View {
        let groups = store.state.recipeGroups ?? []
        let count = groups.reduce(0) { $0 + $1.items.count }

        VStack(alignment: .leading, spacing: 24) {
            RecipeSetup()
            if count == 0 {
                EmptyCardContent(
                    symbol: "frying.pan.fill",
                    title: store.state.recipeGroups == nil ? "Pas encore de recettes" : "Aucune recette pour ces styles",
                    message: store.state.recipeGroups == nil
                        ? "Choisis combien de petits-déjeuners, repas et collations, puis appuie sur Proposer."
                        : "Retire un style ou change de repas, puis relance."
                )
                .card()
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.id) { gi, group in
                    if !group.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(group.type.label) {
                                Text("\(group.items.count)").foregroundStyle(.secondary)
                            }
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, _ in
                                RecipeCard(group: gi, index: index)
                            }
                        }
                    }
                }
                RecipeGroceries()
                WeekPlan()
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
            Text("Combien de recettes ?").font(.headline)
            ForEach(MealType.allCases) { type in
                CountStepper(title: type.label, value: Binding(
                    get: { counts[type] ?? 0 },
                    set: { value in
                        var c = store.recipeCounts
                        c[type] = min(14, max(0, value))
                        store.state.recipeCounts = c
                    }
                ))
            }

            if !store.state.favorites.isEmpty {
                Divider()
                Text("Mes favoris").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(Array(store.state.favorites.enumerated()), id: \.offset) { _, fav in
                        if let tpl = NutritionData.recipe(fav.tpl) {
                            ChoiceChip(title: tpl.name, symbol: "star.fill", isOn: false) { addFavorite(fav, name: tpl.name) }
                        }
                    }
                }
            }

            Divider()
            Text("Style").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout {
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
            }

            Button {
                withAnimation(.snappy) {
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

            Text("Les recettes suivent ton régime et tes goûts, et les quantités collent aux macros du repas choisi.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        withAnimation(.snappy) {
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

    var body: some View {
        if let groups = store.state.recipeGroups, groups.indices.contains(group), groups[group].items.indices.contains(index) {
            let g = groups[group]
            let pick = g.items[index]
            let settings = store.settings
            if let built = settings.build(pick, target: settings.typeTarget(g.type)) {
                let key = NutritionStore.recipeKey(group, index)
                let editing = session.editingRecipe == key
                let isFavorite = store.state.favorites.contains { $0.tpl == pick.tpl }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(built.template.name).font(.title3.bold())
                        Spacer()
                        Menu {
                            Button("Changer de recette", systemImage: "arrow.triangle.2.circlepath") { change() }
                            Button(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: isFavorite ? "star.slash" : "star") {
                                toggleFavorite(pick, type: g.type, isFavorite: isFavorite)
                            }
                            Button("Supprimer", systemImage: "trash", role: .destructive) { delete() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .accessibilityLabel("Options")
                    }

                    HStack(spacing: 6) {
                        Label("\(built.template.minutes) min", systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.field, in: Capsule())
                        ForEach(built.template.tags, id: \.self) { tag in
                            if let style = RecipeStyle(rawValue: tag) {
                                Text(style.label)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .foregroundStyle(Color.accentColor)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                        if isFavorite {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
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
                            withAnimation(.snappy) { session.editingRecipe = editing ? nil : key }
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
                .card()
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
            withAnimation(.snappy) {
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
        withAnimation(.snappy) {
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
        withAnimation(.snappy) { session.page = .today }
    }
}

// MARK: - Groceries and plan

private struct RecipeGroceries: View {
    @Environment(NutritionStore.self) private var store
    @Environment(NutritionSession.self) private var session

    var body: some View {
        let totals = store.recipeTotals()
        let servings = (store.state.recipeGroups ?? []).reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.servings } }

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Les courses pour tes \(servings) portions")
            Text("Quand plusieurs recettes utilisent le même produit, les quantités sont additionnées.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(totals) { t in
                    HStack(spacing: 10) {
                        GradeBadge(grade: store.settings.score(t.food).grade, size: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.food.name).font(.subheadline)
                            if t.recipes > 1 {
                                Text("dans \(t.recipes) recettes").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(NutritionFormat.weight(t.grams)).font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                    }
                }
                Button {
                    let n = store.sendRecipesToList()
                    withAnimation(.snappy) { session.page = .groceries }
                    session.flash("\(n) produits envoyés à ta liste de courses")
                } label: {
                    Label("Tout envoyer à ma liste de courses", systemImage: "cart.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .glassProminentButton()
                .controlSize(.large)
                .padding(.top, 6)
            }
            .card()
        }
    }
}

private struct WeekPlan: View {
    @Environment(NutritionStore.self) private var store

    var body: some View {
        let plan = store.plan()
        let groups = store.state.recipeGroups ?? []

        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Ma semaine") {
                Button("Répartir automatiquement") { store.state.planOverrides = [:] }
            }
            Text("Tes portions réparties jour par jour. Touche un repas pour le changer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(plan.days) { day in
                    if day.offset > 0 { Divider().padding(.vertical, 8) }
                    Text(dayName(day))
                        .font(.headline)
                        .foregroundStyle(day.offset == 0 ? Color.accentColor : Color.primary)
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
                            Text(cell.slot.label).foregroundStyle(.secondary)
                        }
                        .pickerStyle(.menu)
                    }
                }
                if plan.extra > 0 {
                    Label("\(plan.extra) portion\(plan.extra > 1 ? "s" : "") en trop pour la semaine.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.top, 10)
                }
            }
            .card()
        }
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

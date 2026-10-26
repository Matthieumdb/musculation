import SwiftUI
import SwiftData

struct NutritionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(NutritionStore.self) private var store

    @State private var isImporting = false
    @State private var pendingImport: PortionImport.Result?
    @State private var isConfirmingReset = false
    @State private var alertMessage: String?

    var body: some View {
        @Bindable var store = store
        let breakdown = store.settings.computedTargets()
        let targets = store.settings.dayTargets

        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Prénom", text: $store.state.settings.profile.name)
                        .textContentType(.givenName)
                    Picker("Sexe", selection: $store.state.settings.profile.sex) {
                        Text("Homme").tag(Sex.m)
                        Text("Femme").tag(Sex.f)
                    }
                    .pickerStyle(.segmented)
                    numberRow("Âge", value: $store.state.settings.profile.age, unit: "ans")
                    numberRow("Taille", value: $store.state.settings.profile.height, unit: "cm")
                    numberRow("Poids", value: $store.state.settings.profile.weight, unit: "kg")
                    Picker("Activité", selection: $store.state.settings.profile.act) {
                        ForEach(NutritionData.activityLabels.indices, id: \.self) { Text(NutritionData.activityLabels[$0]).tag($0) }
                    }
                    Picker("Objectif", selection: $store.state.settings.profile.goal) {
                        ForEach(NutritionData.goalLabels.indices, id: \.self) { Text(NutritionData.goalLabels[$0]).tag($0) }
                    }
                    numberRow("Protéines", value: $store.state.settings.profile.protKg, unit: "g / kg", digits: 2)
                    numberRow("Lipides minimum", value: $store.state.settings.profile.fatKg, unit: "g / kg", digits: 2)
                }

                Section {
                    if !store.settings.manual.on {
                        LabeledContent("Métabolisme de base", value: "\(Int(breakdown.bmr.rounded())) kcal")
                        LabeledContent("Dépense du jour", value: "\(Int(breakdown.tdee.rounded())) kcal")
                    }
                    LabeledContent {
                        Text("\(Int(targets.kcal)) kcal").font(.headline)
                    } label: {
                        Text("Objectif calories")
                        let loss = max(0, (breakdown.tdee - targets.kcal) * 7 / 7700)
                        if loss > 0.05 { Text("≈ \(loss.kgText) par semaine") }
                    }
                    if store.settings.adj.kcal != 0 && !store.settings.manual.on {
                        LabeledContent("Ajustement auto (poids)") {
                            HStack {
                                Text("\(store.settings.adj.kcal > 0 ? "+" : "")\(Int(store.settings.adj.kcal)) kcal")
                                Button("Remettre à 0") { store.state.settings.adj = Adjustment() }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    HStack {
                        targetPill("\(Int(targets.p)) g", "Prot.", Theme.protein)
                        targetPill("\(Int(targets.c)) g", "Gluc.", Theme.carbs)
                        targetPill("\(Int(targets.f)) g", "Lip.", Theme.fat)
                    }
                    Toggle("Fixer mes cibles à la main", isOn: Binding(
                        get: { store.settings.manual.on },
                        set: { on in
                            if on {
                                let c = store.settings.computedTargets().targets
                                store.state.settings.manual = ManualTargets(on: true, kcal: c.kcal, p: c.p, c: c.c, f: c.f)
                            } else {
                                store.state.settings.manual.on = false
                            }
                        }
                    ))
                    if store.settings.manual.on {
                        numberRow("Calories", value: $store.state.settings.manual.kcal, unit: "kcal", digits: 0)
                        numberRow("Protéines", value: $store.state.settings.manual.p, unit: "g", digits: 0)
                        numberRow("Glucides", value: $store.state.settings.manual.c, unit: "g", digits: 0)
                        numberRow("Lipides", value: $store.state.settings.manual.f, unit: "g", digits: 0)
                    }
                } header: {
                    Text("Mes cibles")
                } footer: {
                    Text("Calculées avec la formule de Mifflin-St Jeor. Chaque semaine, ta tendance de poids corrige les calories de 100 kcal si besoin.")
                }

                MealsSection()

                Section {
                    Picker("Régime", selection: $store.state.settings.diet.type) {
                        ForEach(DietType.allCases) { type in
                            VStack(alignment: .leading) {
                                Text(type.label)
                                Text(type.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if store.settings.diet.type != .veg && store.settings.diet.type != .vegan {
                        Toggle("Sans produits de la mer", isOn: $store.state.settings.diet.seafood)
                        if store.settings.diet.seafood {
                            Toggle("…sauf le thon en boîte", isOn: $store.state.settings.diet.tuna)
                        }
                    }
                } header: {
                    Text("Mon régime")
                }

                Section {
                    NavigationLink {
                        TastesView()
                    } label: {
                        LabeledContent("Mes goûts", value: "\(store.settings.prefs.values.filter { $0 == 1 }.count) aimés · \(store.settings.prefs.values.filter { $0 == -1 }.count) évités")
                    }
                    Picker("Devise", selection: $store.state.settings.currency) {
                        ForEach(["€", "$", "£"], id: \.self) { Text($0).tag($0) }
                    }
                } footer: {
                    Text("Les aliments que tu n'aimes pas disparaissent des suggestions, ceux que tu aimes passent en premier, y compris dans les recettes.")
                }

                Section {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Importer une sauvegarde Portion", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) {
                        store.todayLog = []
                        alertMessage = "Journal du jour effacé."
                    } label: {
                        Label("Effacer le journal du jour", systemImage: "eraser")
                    }
                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label("Réinitialiser la nutrition", systemImage: "trash")
                    }
                } header: {
                    Text("Données")
                } footer: {
                    Text("Exporte d'abord tes données depuis Portion (Réglages > Mes données > Exporter), puis importe le fichier ici. La sauvegarde de Musculation inclut aussi la nutrition.")
                }
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                do {
                    pendingImport = try PortionImport.read(result.get())
                } catch {
                    alertMessage = (error as? LocalizedError)?.errorDescription ?? "Fichier illisible."
                }
            }
            .confirmationDialog(
                "Remplacer tes données nutrition ?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                titleVisibility: .visible
            ) {
                Button("Importer") { applyImport() }
            } message: {
                if let pendingImport {
                    Text("La sauvegarde contient \(pendingImport.days) jours de repas et \(pendingImport.weights.count) pesées. Les pesées s'ajoutent à celles de l'app.")
                }
            }
            .confirmationDialog("Tout réinitialiser ?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Réinitialiser", role: .destructive) { store.reset() }
            } message: {
                Text("Profil, repas, courses et recettes seront effacés. Tes pesées restent dans l'app.")
            }
            .alert(alertMessage ?? "", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK") {}
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String, digits: Int = 1) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...digits)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private func targetPill(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).fontDesign(.rounded).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func applyImport() {
        guard let result = pendingImport else { return }
        pendingImport = nil
        store.replace(with: result.state)
        PortionImport.mergeWeights(result.weights, into: context)
        alertMessage = "Données Portion importées."
    }
}

private struct MealsSection: View {
    @Environment(NutritionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let slots = store.settings.slots
        let sk = slots.reduce(0) { $0 + $1.pk }, sp = slots.reduce(0) { $0 + $1.pp }

        Section {
            ForEach($store.state.settings.slots) { $slot in
                HStack {
                    Picker("Type", selection: $slot.type) {
                        ForEach(MealType.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    percentField(value: $slot.pk, label: "kcal")
                    percentField(value: $slot.pp, label: "prot.")
                }
            }
            .onDelete { offsets in
                guard store.state.settings.slots.count > offsets.count else { return }
                store.state.settings.slots.remove(atOffsets: offsets)
            }
            .onMove { from, to in store.state.settings.slots.move(fromOffsets: from, toOffset: to) }

            Button {
                store.state.settings.slots.append(MealSlot(id: "s\(Int(Date.now.timeIntervalSince1970 * 1000))", type: .snack, pk: 10, pp: 10))
            } label: {
                Label("Ajouter un repas", systemImage: "plus")
            }

            ForEach(store.settings.slotTargets) { slot in
                LabeledContent(slot.label) {
                    Text("\(Int(slot.target.kcal)) kcal · P \(Int(slot.target.p)) · G \(Int(slot.target.c)) · L \(Int(slot.target.f))")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Mes repas")
        } footer: {
            if sk != 100 || sp != 100 {
                Text("Les parts doivent faire 100 % (calories : \(Int(sk)) %, protéines : \(Int(sp)) %). Je normalise automatiquement.")
                    .foregroundStyle(.orange)
            } else {
                Text("Part des calories et des protéines de la journée pour chaque repas. Glisse vers la gauche pour supprimer.")
            }
        }
    }

    private func percentField(value: Binding<Double>, label: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                TextField("%", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 38)
                Text("%").foregroundStyle(.secondary)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct TastesView: View {
    @Environment(NutritionStore.self) private var store
    @State private var search = ""
    @State private var copied = false

    var body: some View {
        let settings = store.settings
        let visible = NutritionData.foods.filter { settings.excluded($0) == nil }
        let query = normalized(search.trimmingCharacters(in: .whitespaces))

        List {
            if query.isEmpty {
                let likes = visible.filter { settings.pref($0) == 1 }
                let dislikes = visible.filter { settings.pref($0) == -1 }
                if likes.isEmpty && dislikes.isEmpty {
                    Text("Rien de noté pour l'instant. Cherche un aliment ci-dessus.")
                        .foregroundStyle(.secondary)
                }
                if !likes.isEmpty {
                    Section("Tu aimes") { ForEach(likes) { row($0) } }
                }
                if !dislikes.isEmpty {
                    Section("Tu n'aimes pas") { ForEach(dislikes) { row($0) } }
                }
                Section {
                    Button(copied ? "Copié !" : "Copier mes goûts pour Claude", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = tastesText(settings)
                        copied = true
                    }
                } footer: {
                    Text("Colle-les dans une conversation avec Claude pour qu'il te propose des repas à ton goût.")
                }
            } else {
                let hits = visible.filter {
                    normalized($0.name).contains(query) || normalized($0.fam.label).contains(query)
                }
                if hits.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(hits.prefix(40)) { row($0) }
            }
        }
        .searchable(text: $search, prompt: "Chercher un aliment")
        .navigationTitle("Mes goûts")
    }

    private func row(_ food: Food) -> some View {
        let value = store.settings.pref(food)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                Text(food.fam.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                set(food, 1)
            } label: {
                Image(systemName: value == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(value == 1 ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("J'aime")
            Button {
                set(food, -1)
            } label: {
                Image(systemName: value == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundStyle(value == -1 ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("J'aime pas")
        }
        .font(.body)
        .imageScale(.large)
    }

    private func set(_ food: Food, _ value: Int) {
        if store.state.settings.prefs[food.id] == value {
            store.state.settings.prefs[food.id] = nil
        } else {
            store.state.settings.prefs[food.id] = value
        }
    }

    private func tastesText(_ s: NutritionSettings) -> String {
        let names = { (v: Int) in NutritionData.foods.filter { s.pref($0) == v }.map(\.name).joined(separator: ", ") }
        var diet = s.diet.type.label
        if s.diet.seafood && s.diet.type != .veg && s.diet.type != .vegan {
            diet += ", sans produits de la mer" + (s.diet.tuna ? " sauf le thon en boîte" : "")
        }
        let liked = names(1), disliked = names(-1)
        return "Mon régime : \(diet)\nJ'aime : \(liked.isEmpty ? "—" : liked)\nJe n'aime pas : \(disliked.isEmpty ? "—" : disliked)"
    }
}

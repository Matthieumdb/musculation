import SwiftUI

/// Finds a food by name: the app's basic foods first, then Open Food Facts products.
struct FoodSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NutritionStore.self) private var store
    var onPick: (Product) -> Void

    @State private var query = ""
    @State private var results: [Product] = []
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        let settings = store.settings
        let basics = query.count < 2 ? [] : NutritionData.foods
            .filter { $0.name.localizedStandardContains(query) && settings.allowed($0) }
            .prefix(8)

        NavigationStack {
            List {
                if !basics.isEmpty {
                    Section("Aliments de base") {
                        ForEach(Array(basics)) { food in
                            row(Product(food: food))
                        }
                    }
                }
                if query.count >= 2 {
                    Section {
                        if isSearching && results.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else if let error {
                            Text(error).foregroundStyle(.secondary)
                        } else if results.isEmpty {
                            Text("Aucun produit trouvé.").foregroundStyle(.secondary)
                        }
                        ForEach(results) { row($0) }
                    } header: {
                        Text("Open Food Facts")
                    } footer: {
                        Text("Valeurs pour 100 g, données ouvertes et collaboratives.")
                    }
                }
            }
            .overlay {
                if query.count < 2 {
                    ContentUnavailableView("Cherche un aliment", systemImage: "magnifyingglass",
                                           description: Text("Par exemple « skyr », « riz basmati » ou une marque."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Aliment ou marque")
            .autocorrectionDisabled()
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task(id: query) { await search() }
        }
    }

    private func row(_ product: Product) -> some View {
        Button {
            onPick(product)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ProductThumb(product: product, grade: store.settings.score(product).grade, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).lineLimit(2)
                    Text(([product.brand] + ["\(Int(product.n.kcal.rounded())) kcal", "P \(Int(product.n.p.rounded())) g"]).filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            error = nil
            return
        }
        // Waits for a pause in typing; a new keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await OpenFoodFacts.search(text)
            guard !Task.isCancelled else { return }
            results = found
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            self.error = (error as? LocalizedError)?.errorDescription
        }
    }
}

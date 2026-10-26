import SwiftUI
import SwiftData

enum NutritionPage: String, CaseIterable, Identifiable {
    case today, groceries, recipes, stats
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Aujourd'hui"
        case .groceries: "Courses"
        case .recipes: "Recettes"
        case .stats: "Bilan"
        }
    }
}

enum ScanTarget: String, Identifiable {
    case meal, groceries
    var id: String { rawValue }
}

/// What the nutrition screens share while the app is open, without saving it.
@MainActor
@Observable
final class NutritionSession {
    var page: NutritionPage = .today
    var slotId: String?
    /// Grams per cart item once computed; nil while the meal is being built.
    var doses: [Double]?
    var scanTarget: ScanTarget?
    var isLookingUp = false
    var mealError: String?
    var groceryError: String?

    /// Product scanned in the groceries page, with the list row it may cover.
    var groceryItem: Product?
    var groceryMatch: Int?
    var groceryTake: Int?

    var editingRecipe: String?
    var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func flash(_ text: String) {
        withAnimation(.appSpring) { toast = text }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.appSpring) { self?.toast = nil }
        }
    }

    func lookup(_ code: String, for target: ScanTarget, store: NutritionStore) async {
        mealError = nil
        groceryError = nil
        isLookingUp = true
        defer { isLookingUp = false }
        do {
            let product = try await OpenFoodFacts.product(code: code)
            switch target {
            case .meal:
                doses = nil
                store.addToCart(product)
                let grade = store.settings.score(product).grade
                flash("\(product.name) ajouté · note \(grade.rawValue)")
            case .groceries:
                groceryItem = product
                groceryMatch = store.settings.matchRow(product, in: store.state.shopList)
                groceryTake = nil
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Produit introuvable."
            if target == .meal { mealError = message } else { groceryError = message }
        }
    }
}

struct NutritionView: View {
    @Environment(NutritionStore.self) private var store
    @State private var session = NutritionSession()
    @State private var isShowingSettings = false

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Section", selection: $session.page) {
                        ForEach(NutritionPage.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch session.page {
                    case .today: TodayPage()
                    case .groceries: GroceriesPage()
                    case .recipes: RecipesPage()
                    case .stats: NutritionStatsPage()
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AppBackground() }
            .navigationTitle("Nutrition")
            .navigationSubtitleIfAvailable(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Réglages nutrition", systemImage: "person.crop.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let toast = session.toast { Toast(text: toast) }
                    actions
                }
            }
            .sheet(isPresented: $isShowingSettings) { NutritionSettingsView() }
            .sheet(item: $session.scanTarget) { target in
                BarcodeScannerSheet { code in
                    Task { await session.lookup(code, for: target, store: store) }
                }
            }
        }
        .environment(session)
        .onAppear {
            if session.slotId == nil { session.slotId = store.settings.guessSlot() }
        }
    }

    private var subtitle: String {
        let t = store.settings.dayTargets
        return "Objectif \(Int(t.kcal)) kcal · \(Int(t.p)) g de protéines"
    }

    /// Floating Liquid Glass buttons of the current page.
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            switch session.page {
            case .today:
                if session.doses == nil {
                    Button {
                        session.scanTarget = .meal
                    } label: {
                        Label("Scanner", systemImage: "barcode.viewfinder")
                            .padding(.horizontal, 4)
                    }
                    .glassButton()

                    Button {
                        hideKeyboard()
                        withAnimation(.appSpring) {
                            session.doses = PortionSolver.solve(store.state.cart, target: store.remaining(for: session.slotId))
                        }
                    } label: {
                        Text(store.state.cart.isEmpty ? "Calculer" : "Calculer (\(store.state.cart.count))")
                            .frame(maxWidth: .infinity)
                    }
                    .glassProminentButton()
                    .disabled(store.state.cart.isEmpty)
                } else {
                    Button {
                        withAnimation(.appSpring) { session.doses = nil }
                    } label: {
                        Text("Modifier").padding(.horizontal, 6)
                    }
                    .glassButton()

                    Button {
                        if let doses = session.doses, let slot = session.slotId ?? store.settings.slotTargets.first?.id {
                            withAnimation(.appSpring) {
                                store.logMeal(grams: doses, slot: slot)
                                session.doses = nil
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            session.flash("Repas noté. Bon appétit !")
                        }
                    } label: {
                        Label("J'ai mangé ça", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .glassProminentButton()
                }
            case .groceries:
                if session.groceryItem == nil {
                    Button {
                        session.scanTarget = .groceries
                    } label: {
                        Label("Scanner un produit", systemImage: "barcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .glassProminentButton()
                }
            case .recipes, .stats:
                EmptyView()
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

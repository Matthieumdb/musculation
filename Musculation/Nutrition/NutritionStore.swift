import Foundation
import Observation
import SwiftData

/// Nutrition data of the app, saved as one JSON file next to the SwiftData store.
/// Body weight is not stored here: it comes from the shared `BodyWeightEntry` records.
@MainActor
@Observable
final class NutritionStore {
    static let shared = NutritionStore()

    var state: NutritionState {
        didSet { scheduleSave() }
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "nutrition.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(NutritionState.self, from: data) {
            state = decoded
        } else {
            state = NutritionState()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: Self.fileURL, options: .atomic)
        } catch {}
    }

    // MARK: Shortcuts

    var settings: NutritionSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    var todayLog: [LogEntry] {
        get { state.logs[DayKey.today] ?? [] }
        set { state.logs[DayKey.today] = newValue }
    }

    func eaten(slot: String? = nil) -> Macros {
        todayLog.filter { slot == nil || $0.slot == slot }.reduce(Macros.zero) { $0 + $1.macros }
    }

    func remaining(for slotId: String?) -> Macros {
        let slots = settings.slotTargets
        guard let slot = slots.first(where: { $0.id == slotId }) ?? slots.first else { return .zero }
        return (slot.target - eaten(slot: slot.id)).floored
    }

    // MARK: Meal

    func addToCart(_ product: Product) {
        var item = product
        if item.foodId == nil { item.fam = item.guessedAisle }
        if item.fixed == nil && item.fam == .legumes { item.fixed = NutritionData.vegetableFixedGrams }
        state.cart.append(item)
    }

    func logMeal(grams: [Double], slot: String) {
        var log = todayLog
        for (item, g) in zip(state.cart, grams) where g > 0 {
            let m = item.n.macros * (g / 100)
            log.append(LogEntry(name: item.name, slot: slot, g: g, kcal: m.kcal, p: m.p, c: m.c, f: m.f))
        }
        todayLog = log
        state.cart = []
    }

    // MARK: Groceries

    func addToList(_ product: Product, aisle: Aisle) {
        var ref = product
        ref.fixed = nil
        let row = ShopRow(fam: aisle, ref: ref)
        if let i = state.shopList.firstIndex(where: { $0.title == product.name }) {
            state.shopList[i] = row
        } else {
            state.shopList.append(row)
        }
    }

    // MARK: Recipes

    var recipeCounts: [MealType: Int] {
        if let counts = state.recipeCounts { return counts }
        var counts: [MealType: Int] = [:]
        for type in MealType.allCases {
            let n = settings.slots.filter { $0.type == type }.count
            counts[type] = type == .meal ? max(1, n) : n
        }
        return counts
    }

    /// Draw without replacement: a recipe comes back only once all the others have been shown.
    func drawRecipes(_ n: Int, type: MealType, avoid: [String] = []) -> [RecipePick] {
        let s = settings
        let pool = s.pool(for: type, styles: state.recipeStyles)
        var out: [RecipePick] = []
        var used = Set(avoid)
        var seen = Set(state.recipeSeen)
        let favIds = Set(state.favorites.map(\.tpl))
        for _ in 0..<n {
            var candidates = pool.filter { !used.contains($0.id) && !seen.contains($0.id) }
            if candidates.isEmpty {
                for r in pool { seen.remove(r.id) }
                candidates = pool.filter { !used.contains($0.id) }
            }
            if candidates.isEmpty { candidates = pool }
            guard !candidates.isEmpty else { break }
            // Small bonus for recipes with liked foods, without crowding out the others
            let w = candidates.map { 1 + 0.25 * Double(min(s.likes($0), 3)) + (favIds.contains($0.id) ? 1 : 0) }
            var x = Double.random(in: 0..<w.reduce(0, +))
            var pick = candidates[0]
            for (i, c) in candidates.enumerated() {
                x -= w[i]
                if x <= 0 { pick = c; break }
            }
            used.insert(pick.id)
            seen.insert(pick.id)
            out.append(RecipePick(tpl: pick.id, picks: s.pickParts(pick)))
        }
        state.recipeSeen = Array(seen)
        return out
    }

    func newRecipes() {
        let counts = recipeCounts
        state.recipeGroups = MealType.allCases.compactMap { type in
            let n = counts[type] ?? 0
            return n > 0 ? RecipeGroup(type: type, items: drawRecipes(n, type: type)) : nil
        }
        state.planOverrides = [:]
    }

    struct IngredientTotal: Identifiable {
        var food: Food
        var grams: Double
        var recipes: Int
        var id: String { food.id }
    }

    /// Every ingredient of the selected recipes, added up across recipes and servings.
    func recipeTotals() -> [IngredientTotal] {
        var sum: [String: IngredientTotal] = [:]
        for group in state.recipeGroups ?? [] {
            let target = settings.typeTarget(group.type)
            for pick in group.items {
                guard let built = settings.build(pick, target: target) else { continue }
                for it in built.items where it.grams > 0 {
                    var x = sum[it.food.id] ?? IngredientTotal(food: it.food, grams: 0, recipes: 0)
                    x.grams += it.grams * Double(pick.servings)
                    x.recipes += 1
                    sum[it.food.id] = x
                }
            }
        }
        let order = Aisle.allCases
        return sum.values.sorted {
            let a = order.firstIndex(of: $0.food.fam) ?? 0, b = order.firstIndex(of: $1.food.fam) ?? 0
            return a != b ? a < b : $0.grams > $1.grams
        }
    }

    /// Replaces the recipe rows of the grocery list with the current recipes' totals.
    func sendRecipesToList() -> Int {
        let totals = recipeTotals()
        let ids = Set(totals.map(\.food.id))
        state.shopList.removeAll { $0.fromRecipes || $0.ref?.foodId.map { ids.contains($0) } == true }
        for t in totals {
            state.shopList.append(ShopRow(fam: t.food.fam, ref: Product(food: t.food), fixedG: t.grams.rounded(), fromRecipes: true))
        }
        return totals.count
    }

    struct PlanCell: Identifiable {
        var id: String
        var slot: SlotTarget
        var key: String
    }

    struct PlanDay: Identifiable {
        var offset: Int
        var date: Date
        var cells: [PlanCell]
        var id: Int { offset }
    }

    static func recipeKey(_ group: Int, _ index: Int) -> String { "\(group):\(index)" }

    /// Servings laid out in order over the week's slots, alternating recipes (A, B, A, B…).
    func plan() -> (days: [PlanDay], extra: Int) {
        var queues: [MealType: [String]] = [:]
        for (gi, group) in (state.recipeGroups ?? []).enumerated() {
            var left = group.items.enumerated().map { (key: Self.recipeKey(gi, $0.offset), n: $0.element.servings) }
            var queue: [String] = []
            while left.contains(where: { $0.n > 0 }) {
                for i in left.indices where left[i].n > 0 {
                    queue.append(left[i].key)
                    left[i].n -= 1
                }
            }
            queues[group.type, default: []] += queue
        }
        var days: [PlanDay] = []
        for d in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: d, to: .now) ?? .now
            var cells: [PlanCell] = []
            for slot in settings.slotTargets {
                let id = "\(d)-\(slot.id)"
                var auto = ""
                if var q = queues[slot.type], !q.isEmpty {
                    auto = q.removeFirst()
                    queues[slot.type] = q
                }
                cells.append(PlanCell(id: id, slot: slot, key: state.planOverrides[id] ?? auto))
            }
            days.append(PlanDay(offset: d, date: date, cells: cells))
        }
        return (days, queues.values.reduce(0) { $0 + $1.count })
    }

    // MARK: Stats

    func dayStats(_ n: Int, weights: [String: Double]) -> [DayStat] {
        (0..<n).reversed().map { i in
            let day = DayKey.offset(i)
            let log = state.logs[day] ?? []
            return DayStat(day: day, logged: !log.isEmpty, macros: log.reduce(Macros.zero) { $0 + $1.macros }, weight: weights[day])
        }
    }

    // MARK: Body weight

    /// One weigh-in per day, the latest of the day.
    static func weightsByDay(_ entries: [BodyWeightEntry]) -> [String: Double] {
        var out: [String: (Date, Double)] = [:]
        for e in entries {
            let key = DayKey.of(e.date)
            if let current = out[key], current.0 > e.date { continue }
            out[key] = (e.date, e.weight)
        }
        return out.mapValues { $0.1 }
    }

    /// Runs the weekly calorie check after a weigh-in.
    func checkAdjustment(entries: [BodyWeightEntry]) {
        var s = settings
        if s.checkAdjustment(weights: Self.weightsByDay(entries)) { settings = s }
    }

    // MARK: Backup

    func replace(with state: NutritionState) {
        self.state = state
        saveNow()
    }

    func reset() {
        state = NutritionState()
        saveNow()
    }
}

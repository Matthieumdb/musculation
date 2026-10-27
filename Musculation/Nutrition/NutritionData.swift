import Foundation

/// Built-in foods and recipe templates, bundled from Portion (nutrition-data.json).
enum NutritionData {
    private struct Payload: Decodable {
        var foods: [Food]
        var recipes: [RecipeTemplate]
        var quick: [String]
    }

    private static let loaded: Payload = {
        guard let url = Bundle.main.url(forResource: "nutrition-data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return Payload(foods: [], recipes: [], quick: []) }
        return decoded
    }()

    static var foods: [Food] { loaded.foods }
    static var recipes: [RecipeTemplate] { loaded.recipes }
    /// Foods offered as one-tap chips when there is no barcode.
    static var quick: [String] { loaded.quick }

    private static let byId: [String: Food] = Dictionary(uniqueKeysWithValues: loaded.foods.map { ($0.id, $0) })

    static func food(_ id: String?) -> Food? {
        id.flatMap { byId[$0] }
    }

    static func recipe(_ id: String) -> RecipeTemplate? {
        loaded.recipes.first { $0.id == id }
    }

    /// Weekly budget per aisle for the reference targets (`base`), scaled to the profile.
    /// `by` is what sets the quantity: a macro in grams, the weight itself, or calories.
    struct AisleBudget {
        enum By { case p, c, f, grams, kcal }
        var by: By
        var budget: Double
        var count: Int
    }

    static let budgets: [Aisle: AisleBudget] = [
        .viandes: AisleBudget(by: .p, budget: 720, count: 2),
        .oeufs: AisleBudget(by: .grams, budget: 660, count: 1),
        .laitiers: AisleBudget(by: .p, budget: 190, count: 1),
        .fromages: AisleBudget(by: .grams, budget: 150, count: 1),
        .feculents: AisleBudget(by: .c, budget: 1000, count: 3),
        .legumes: AisleBudget(by: .grams, budget: 2400, count: 3),
        .fruits: AisleBudget(by: .grams, budget: 1200, count: 2),
        .graisses: AisleBudget(by: .f, budget: 120, count: 1),
        .sauces: AisleBudget(by: .grams, budget: 450, count: 2),
        .poudre: AisleBudget(by: .grams, budget: 210, count: 1),
        .extras: AisleBudget(by: .kcal, budget: 700, count: 1),
    ]

    /// Targets the grocery budgets were written for.
    static let base = Macros(kcal: 2100, p: 180, c: 185, f: 70)

    /// Rough supermarket prices per kg.
    static let aislePrice: [Aisle: Double] = [
        .viandes: 12, .oeufs: 4.5, .laitiers: 4, .fromages: 12, .feculents: 2.5, .legumes: 3,
        .fruits: 3.5, .graisses: 10, .sauces: 5, .poudre: 28, .extras: 10,
    ]
    static let foodPrice: [Int: Double] = [
        0: 13, 1: 12, 2: 9, 3: 13, 5: 25, 7: 16, 8: 14, 12: 4, 19: 2.5, 21: 1.8, 22: 2.2, 23: 1.5,
        25: 2, 41: 9, 42: 12, 43: 18, 48: 30, 49: 22, 50: 25, 51: 25, 52: 11, 56: 14,
    ]

    static let activityFactors = [1.2, 1.375, 1.55, 1.725]
    static let activityLabels = [
        "Sédentaire", "Légèrement actif (1 à 3 séances)", "Modérément actif (3 à 5 séances)", "Très actif (6 à 7 séances)",
    ]
    static let goalOffsets: [Double] = [-750, -500, -300, 0, 250]
    static let goalLabels = [
        "Sèche rapide (−750 kcal)", "Perte de gras (−500 kcal)", "Perte douce (−300 kcal)", "Maintien", "Prise de muscle (+250 kcal)",
    ]

    /// Vegetables added to a meal start at a fixed quantity.
    static let vegetableFixedGrams: Double = 150
    static let maxGrams: Double = 600
}

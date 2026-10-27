import Foundation

/// Calories and macros, per 100 g for a food or as totals for a meal.
struct Macros: Codable, Hashable {
    var kcal: Double = 0
    var p: Double = 0
    var c: Double = 0
    var f: Double = 0

    static let zero = Macros()

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, p: a.p + b.p, c: a.c + b.c, f: a.f + b.f)
    }

    static func - (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal - b.kcal, p: a.p - b.p, c: a.c - b.c, f: a.f - b.f)
    }

    static func * (a: Macros, k: Double) -> Macros {
        Macros(kcal: a.kcal * k, p: a.p * k, c: a.c * k, f: a.f * k)
    }

    subscript(key: MacroKey) -> Double {
        get {
            switch key {
            case .kcal: kcal
            case .p: p
            case .c: c
            case .f: f
            }
        }
        set {
            switch key {
            case .kcal: kcal = newValue
            case .p: p = newValue
            case .c: c = newValue
            case .f: f = newValue
            }
        }
    }

    /// Clamps every value at zero.
    var floored: Macros { Macros(kcal: max(0, kcal), p: max(0, p), c: max(0, c), f: max(0, f)) }
}

enum MacroKey: String, CaseIterable, Identifiable {
    case kcal, p, c, f
    var id: String { rawValue }
}

/// Full nutrition values per 100 g.
struct Nutrients: Codable, Hashable {
    var kcal: Double
    var p: Double
    var c: Double
    var f: Double
    var sugar: Double?
    var sat: Double?
    var salt: Double?
    var fiber: Double?

    var macros: Macros { Macros(kcal: kcal, p: p, c: c, f: f) }
}

/// Foods counted by the piece or the spoon (eggs, oil).
struct FoodUnit: Codable, Hashable {
    enum Kind: String, Codable { case egg, tbsp }
    var kind: Kind
    var grams: Double
    var step: Double

    func label(count: Double) -> String {
        switch kind {
        case .egg: count > 1 ? "œufs" : "œuf"
        case .tbsp: "c. à soupe"
        }
    }
}

/// Supermarket aisle; drives the weekly grocery budget.
enum Aisle: String, Codable, CaseIterable, Identifiable {
    case viandes, oeufs, laitiers, fromages, feculents, legumes, fruits, graisses, sauces, poudre, extras
    var id: String { rawValue }

    var label: String {
        switch self {
        case .viandes: "Viandes & volaille"
        case .oeufs: "Œufs"
        case .laitiers: "Laitiers protéinés"
        case .fromages: "Fromages"
        case .feculents: "Féculents"
        case .legumes: "Légumes"
        case .fruits: "Fruits"
        case .graisses: "Huiles & oléagineux"
        case .sauces: "Sauces & condiments"
        case .poudre: "Protéine en poudre"
        case .extras: "Plaisirs hors plan"
        }
    }

    var symbol: String {
        switch self {
        case .viandes: "fish.fill"
        case .oeufs: "oval.portrait.fill"
        case .laitiers: "cup.and.saucer.fill"
        case .fromages: "triangle.lefthalf.filled"
        case .feculents: "takeoutbag.and.cup.and.straw.fill"
        case .legumes: "carrot.fill"
        case .fruits: "applelogo"
        case .graisses: "drop.fill"
        case .sauces: "flame.fill"
        case .poudre: "bolt.fill"
        case .extras: "birthday.cake.fill"
        }
    }

    /// Other products of this aisle the plan expects, to explain splits.
    var examples: String? {
        switch self {
        case .viandes: "poulet, dinde, bœuf haché, porc"
        case .laitiers: "skyr, yaourt grec, fromage blanc"
        case .feculents: "riz, pâtes, pommes de terre, avoine"
        case .legumes: "frais ou surgelés"
        case .graisses: "huile, beurre de cacahuète, amandes"
        default: nil
        }
    }
}

/// A food of the built-in table (raw values, CIQUAL rounded).
struct Food: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var fam: Aisle
    var tags: [String]
    var nova: Int
    var n: Nutrients
    var unit: FoodUnit?

    /// Name without "(cru)" and similar, for chips and recipe steps.
    var shortName: String {
        name.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " en mélange", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// A product to eat or to buy: a built-in food or a product scanned on Open Food Facts.
struct Product: Codable, Hashable, Identifiable {
    var id = UUID()
    var foodId: String?
    var code: String?
    var name: String
    var brand: String = ""
    var imageURL: String = ""
    var fam: Aisle
    var tags: [String]?
    var nova: Int?
    var additives: Int = 0
    var categories: [String] = []
    var allergens: [String] = []
    var analysis: [String] = []
    var packG: Double = 0
    var n: Nutrients
    var unit: FoodUnit?
    /// Fixed quantity in grams, nil when the app computes it.
    var fixed: Double?

    init(food: Food) {
        foodId = food.id
        name = food.name
        fam = food.fam
        tags = food.tags
        nova = food.nova
        n = food.n
        unit = food.unit
    }

    init(code: String, name: String, brand: String, imageURL: String, nova: Int?, additives: Int,
         categories: [String], allergens: [String], analysis: [String], packG: Double, n: Nutrients) {
        self.code = code
        self.name = name
        self.brand = brand
        self.imageURL = imageURL
        self.nova = nova
        self.additives = additives
        self.categories = categories
        self.allergens = allergens
        self.analysis = analysis
        self.packG = packG
        self.n = n
        self.fam = .extras
    }
}

/// One food eaten, in the day's log.
struct LogEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var slot: String
    var g: Double
    var kcal: Double
    var p: Double
    var c: Double
    var f: Double

    var macros: Macros { Macros(kcal: kcal, p: p, c: c, f: f) }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, meal, snack
    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        case .meal: "Repas"
        case .snack: "Collation"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .meal: "fork.knife"
        case .snack: "carrot.fill"
        }
    }
}

/// A meal of the day with its share of calories (pk) and protein (pp), in %.
struct MealSlot: Codable, Hashable, Identifiable {
    var id: String
    var type: MealType
    var pk: Double
    var pp: Double
}

/// A meal slot with its computed targets.
struct SlotTarget: Identifiable, Hashable {
    var id: String
    var type: MealType
    var name: String
    var sub: String
    var target: Macros

    var label: String { sub.isEmpty ? name : "\(name) \(sub)" }
}

enum Sex: String, Codable, CaseIterable { case m, f }

enum DietType: String, Codable, CaseIterable, Identifiable {
    case omni, pesc, veg, vegan, nopork
    var id: String { rawValue }

    var label: String {
        switch self {
        case .omni: "Omnivore"
        case .pesc: "Pescétarien"
        case .veg: "Végétarien"
        case .vegan: "Végan"
        case .nopork: "Sans porc"
        }
    }

    var detail: String {
        switch self {
        case .omni: "Tu manges de tout."
        case .pesc: "Pas de viande, mais poisson et fruits de mer."
        case .veg: "Ni viande ni poisson."
        case .vegan: "Aucun produit animal."
        case .nopork: "Tout sauf le porc."
        }
    }
}

struct Profile: Codable, Hashable {
    var name = ""
    var sex = Sex.m
    var age: Double = 30
    var height: Double = 178
    var weight: Double = 78
    var act = 1
    var goal = 1
    var protKg = 2.0
    var fatKg = 0.8
}

struct ManualTargets: Codable, Hashable {
    var on = false
    var kcal: Double = 2100
    var p: Double = 180
    var c: Double = 185
    var f: Double = 70

    var macros: Macros { Macros(kcal: kcal, p: p, c: c, f: f) }
}

struct Diet: Codable, Hashable {
    var type = DietType.omni
    var seafood = true
    var tuna = true
}

/// Weekly calorie correction made from the weight trend.
struct Adjustment: Codable, Hashable {
    var kcal: Double = 0
    var last: String?
    var message: String?
}

struct NutritionSettings: Codable, Hashable {
    var profile = Profile()
    var manual = ManualTargets()
    var slots: [MealSlot] = [
        MealSlot(id: "s1", type: .meal, pk: 43, pp: 39),
        MealSlot(id: "s2", type: .snack, pk: 14, pp: 22),
        MealSlot(id: "s3", type: .meal, pk: 43, pp: 39),
    ]
    var diet = Diet()
    /// Food id → 1 (liked) or -1 (disliked).
    var prefs: [String: Int] = [:]
    var adj = Adjustment()
    var currency = "€"
    /// Today's training adjustment, filled in from the workouts when read through the store. Never saved.
    var training: TrainingDay?
}

/// Calories added on a training day, or taken off a rest day so the week keeps the same average.
struct TrainingDay: Codable, Hashable {
    var kcal: Double
    var trained: Bool
}

/// A line of the weekly grocery list.
struct ShopRow: Codable, Hashable, Identifiable {
    var id = UUID()
    var fam: Aisle
    var ref: Product?
    var name: String?
    /// Quantity set by recipes; otherwise the plan computes it.
    var fixedG: Double?
    var g: Double?
    var got: Double = 0
    var done = false
    var fromRecipes = false
    /// Price per kg entered by the user.
    var ppk: Double?

    var title: String { ref?.name ?? name ?? "" }
}

/// One recipe in the current selection: template, chosen foods per part and servings.
struct RecipePick: Codable, Hashable, Identifiable {
    var id = UUID()
    var tpl: String
    var picks: [String?]
    var servings = 1
}

struct RecipeGroup: Codable, Hashable, Identifiable {
    var type: MealType
    var items: [RecipePick]
    var id: MealType { type }
}

struct FavoriteRecipe: Codable, Hashable {
    var tpl: String
    var picks: [String?]
    var type: MealType
}

/// Everything the nutrition side saves.
struct NutritionState: Codable {
    var settings = NutritionSettings()
    var logs: [String: [LogEntry]] = [:]
    var cart: [Product] = []
    var shopList: [ShopRow] = []
    var variety: [Aisle: Int] = [:]
    var recipeGroups: [RecipeGroup]?
    var recipeCounts: [MealType: Int]?
    var recipeStyles: [String] = []
    var recipeSeen: [String] = []
    var favorites: [FavoriteRecipe] = []
    var planOverrides: [String: String] = [:]
    var statPeriod = 7
    /// Weigh-ins imported from Portion and not yet merged into body weights.
    var pendingWeights: [String: Double]?
}

// MARK: - Built-in data

struct RecipePart: Codable, Hashable {
    enum Role: String, Codable { case P, C, F, V, R, X }
    var role: Role
    var options: [String]
    var grams: Double?
}

struct RecipeTemplate: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var kinds: [MealType]
    var veg: Bool
    var tags: [String]
    var minutes: Int
    var steps: String
    var parts: [RecipePart]
}

enum RecipeStyle: String, CaseIterable, Identifiable {
    case h, g, q, b, w
    var id: String { rawValue }

    var label: String {
        switch self {
        case .h: "Healthy"
        case .g: "Gourmand"
        case .q: "Rapide"
        case .b: "Batch cooking"
        case .w: "Saveurs du monde"
        }
    }
}

extension Aisle: CodingKeyRepresentable {}
extension MealType: CodingKeyRepresentable {}

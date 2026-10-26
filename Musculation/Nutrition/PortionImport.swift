import Foundation
import SwiftData

/// Reads a backup exported from the Portion web app ({ app: "portion", all: { key: JSON } }).
enum PortionImport {
    enum ImportError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Ce fichier n'est pas une sauvegarde Portion." }
    }

    struct Result {
        var state: NutritionState
        var weights: [String: Double]
        var days: Int
    }

    static func read(_ url: URL) throws -> Result {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let all = root["all"] as? [String: String]
        else { throw ImportError.unreadable }

        func value(_ key: String) -> Any? {
            all[key].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        }

        var state = NutritionState()
        if let s = value("settings") as? [String: Any] { state.settings = settings(s) }
        for (key, _) in all where key.hasPrefix("log-") {
            let day = String(key.dropFirst(4))
            let entries = (value(key) as? [[String: Any]] ?? []).map { e in
                LogEntry(name: e["name"] as? String ?? "", slot: e["slot"] as? String ?? "", g: num(e["g"]),
                         kcal: num(e["kcal"]), p: num(e["p"]), c: num(e["c"]), f: num(e["f"]))
            }
            if !entries.isEmpty { state.logs[day] = entries }
        }
        state.cart = (value("cart") as? [[String: Any]] ?? []).compactMap(product)
        state.shopList = (value("shopList") as? [[String: Any]] ?? []).compactMap(shopRow)
        if let v = value("variety") as? [String: Any] {
            for (k, n) in v { if let aisle = Aisle(rawValue: k) { state.variety[aisle] = Int(num(n)) } }
        }
        if let r = value("recipes") as? [String: Any], let groups = r["groups"] as? [[String: Any]] {
            state.recipeGroups = groups.compactMap { g in
                guard let type = MealType(rawValue: g["type"] as? String ?? "") else { return nil }
                let items = (g["items"] as? [[String: Any]] ?? []).map { i in
                    RecipePick(tpl: i["tpl"] as? String ?? "", picks: (i["picks"] as? [Any] ?? []).map { $0 as? String },
                               servings: max(1, Int(num(i["n"] ?? 1))))
                }
                return RecipeGroup(type: type, items: items)
            }
        }
        if let c = value("recipeCounts") as? [String: Any] {
            var counts: [MealType: Int] = [:]
            for (k, n) in c { if let type = MealType(rawValue: k) { counts[type] = Int(num(n)) } }
            state.recipeCounts = counts
        }
        state.recipeStyles = value("recipeStyles") as? [String] ?? []
        state.recipeSeen = value("recSeen") as? [String] ?? []
        state.favorites = (value("recFavs") as? [[String: Any]] ?? []).compactMap { f in
            guard let tpl = f["tpl"] as? String, let type = MealType(rawValue: f["type"] as? String ?? "") else { return nil }
            return FavoriteRecipe(tpl: tpl, picks: (f["picks"] as? [Any] ?? []).map { $0 as? String }, type: type)
        }
        state.planOverrides = value("planOver") as? [String: String] ?? [:]
        if let period = value("statPeriod") { state.statPeriod = Int(num(period)) == 0 ? 7 : Int(num(period)) }

        var weights: [String: Double] = [:]
        for (day, kg) in value("weights") as? [String: Any] ?? [:] { weights[day] = num(kg) }
        return Result(state: state, weights: weights, days: state.logs.count)
    }

    /// Adds the weigh-ins of days that have none yet.
    static func mergeWeights(_ weights: [String: Double], into context: ModelContext) {
        let existing = Set(((try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []).map { DayKey.of($0.date) })
        for (day, kg) in weights where !existing.contains(day) && kg > 0 {
            guard let date = DayKey.date(day), let noon = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) else { continue }
            context.insert(BodyWeightEntry(date: noon, weight: kg))
        }
        try? context.save()
    }

    // MARK: Parsing

    private static func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return 0
    }

    private static func optionalNum(_ v: Any?) -> Double? {
        v == nil || v is NSNull ? nil : num(v)
    }

    private static func settings(_ s: [String: Any]) -> NutritionSettings {
        var out = NutritionSettings()
        if let p = s["profile"] as? [String: Any] {
            out.profile = Profile(
                name: p["name"] as? String ?? "",
                sex: Sex(rawValue: p["sex"] as? String ?? "m") ?? .m,
                age: num(p["age"] ?? 30), height: num(p["height"] ?? 178), weight: num(p["weight"] ?? 78),
                act: Int(num(p["act"] ?? 1)), goal: Int(num(p["goal"] ?? 1)),
                protKg: num(p["protKg"] ?? 2), fatKg: num(p["fatKg"] ?? 0.8)
            )
        }
        if let m = s["manual"] as? [String: Any] {
            out.manual = ManualTargets(on: m["on"] as? Bool ?? false, kcal: num(m["kcal"]), p: num(m["p"]), c: num(m["c"]), f: num(m["f"]))
        }
        if let slots = s["slots"] as? [[String: Any]] {
            let parsed = slots.compactMap { x -> MealSlot? in
                guard let id = x["id"] as? String else { return nil }
                return MealSlot(id: id, type: MealType(rawValue: x["type"] as? String ?? "") ?? .meal, pk: num(x["pk"]), pp: num(x["pp"]))
            }
            if !parsed.isEmpty { out.slots = parsed }
        }
        if let d = s["diet"] as? [String: Any] {
            out.diet = Diet(type: DietType(rawValue: d["type"] as? String ?? "") ?? .omni,
                            seafood: d["seafood"] as? Bool ?? true, tuna: d["tuna"] as? Bool ?? true)
        }
        if let prefs = s["prefs"] as? [String: Any] {
            for (k, v) in prefs { out.prefs[k] = Int(num(v)) }
        }
        if let a = s["adj"] as? [String: Any] {
            out.adj = Adjustment(kcal: num(a["kcal"]), last: a["last"] as? String, message: nil)
        }
        out.currency = s["currency"] as? String ?? "€"
        return out
    }

    private static func nutrients(_ n: [String: Any]) -> Nutrients {
        Nutrients(kcal: num(n["kcal"]), p: num(n["p"]), c: num(n["c"]), f: num(n["f"]),
                  sugar: optionalNum(n["sugar"]), sat: optionalNum(n["sat"]), salt: optionalNum(n["salt"]), fiber: optionalNum(n["fiber"]))
    }

    private static func unit(_ u: Any?) -> FoodUnit? {
        guard let u = u as? [String: Any], let kind = FoodUnit.Kind(rawValue: u["k"] as? String ?? "") else { return nil }
        return FoodUnit(kind: kind, grams: num(u["g"]), step: num(u["step"]))
    }

    private static func product(_ x: [String: Any]) -> Product? {
        guard let n = x["n"] as? [String: Any] else { return nil }
        var p: Product
        if let food = NutritionData.food(x["foodId"] as? String) {
            p = Product(food: food)
        } else {
            p = Product(code: x["code"] as? String ?? "", name: x["name"] as? String ?? x["fr"] as? String ?? "",
                        brand: x["brand"] as? String ?? "", imageURL: x["img"] as? String ?? "",
                        nova: (x["nova"] as? NSNumber)?.intValue, additives: Int(num(x["additives"])),
                        categories: x["cats"] as? [String] ?? [], allergens: x["allergens"] as? [String] ?? [],
                        analysis: x["analysis"] as? [String] ?? [], packG: num(x["packG"]), n: nutrients(n))
            p.unit = unit(x["unit"])
            p.fam = Aisle(rawValue: x["fam"] as? String ?? "") ?? p.guessedAisle
        }
        p.packG = num(x["packG"])
        p.fixed = optionalNum(x["fixed"])
        return p
    }

    private static func shopRow(_ x: [String: Any]) -> ShopRow? {
        guard let fam = Aisle(rawValue: x["fam"] as? String ?? "") else { return nil }
        var row = ShopRow(fam: fam)
        if let ref = x["ref"] as? [String: Any] { row.ref = product(ref) }
        row.name = x["name"] as? String
        row.g = optionalNum(x["g"])
        row.fixedG = optionalNum(x["fixedG"])
        row.got = num(x["got"])
        row.done = x["done"] as? Bool ?? false
        row.fromRecipes = x["fromRec"] as? Bool ?? false
        row.ppk = optionalNum(x["ppk"])
        return row
    }
}

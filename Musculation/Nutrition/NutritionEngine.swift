import Foundation

/// Calculations ported from Portion: targets, scoring, aisles, portion solver, recipes and stats.
enum NutritionEngine {}

// MARK: - Days

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func of(_ date: Date) -> String { formatter.string(from: date) }
    static var today: String { of(.now) }

    /// The day `n` days before today.
    static func offset(_ n: Int) -> String {
        of(Calendar.current.date(byAdding: .day, value: -n, to: .now) ?? .now)
    }

    static func date(_ key: String) -> Date? { formatter.date(from: key) }

    static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let a = date(from), let b = date(to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

// MARK: - Formatting

enum NutritionFormat {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func weight(_ g: Double) -> String {
        if g >= 1000 { return "\(number(g / 1000)) kg" }
        if g >= 100 { return "\(Int((g / 10).rounded()) * 10) g" }
        return "\(Int(g.rounded())) g"
    }

    static func money(_ value: Double, currency: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(2)))) \(currency)"
    }

    static func packs(_ g: Double, packG: Double) -> String? {
        guard packG > 0 else { return nil }
        let k = max(1, Int((g / packG).rounded()))
        return "≈ \(k) paquet\(k > 1 ? "s" : "") de \(weight(packG))"
    }

    static func macroLine(_ n: Nutrients) -> String {
        "\(Int(n.kcal.rounded())) kcal · P \(number(n.p)) · G \(number(n.c)) · L \(number(n.f)) pour 100 g"
    }
}

private func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

/// Products weighed raw or dry (rice, pasta…).
func isWeighedRaw(_ name: String) -> Bool {
    name.range(of: "riz|rice|pâtes|pasta|spaghetti|penne|fusilli|coquillettes|semoule|couscous|quinoa|lentil|avoine|oats|cru|dry",
               options: [.regularExpression, .caseInsensitive]) != nil
}

// MARK: - Targets (Mifflin-St Jeor)

struct EnergyBreakdown {
    var bmr: Double
    var tdee: Double
    var targets: Macros
}

extension NutritionSettings {
    func computedTargets() -> EnergyBreakdown {
        let p = profile
        let bmr = 10 * p.weight + 6.25 * p.height - 5 * p.age + (p.sex == .f ? -161 : 5)
        let tdee = bmr * NutritionData.activityFactors[min(max(p.act, 0), 3)]
        let kcal = ((tdee + NutritionData.goalOffsets[min(max(p.goal, 0), 4)] + adj.kcal) / 50).rounded() * 50
        let prot = (p.protKg * p.weight).rounded()
        let fat = (p.fatKg * p.weight).rounded()
        let carbs = max(0, ((kcal - prot * 4 - fat * 9) / 4).rounded())
        return EnergyBreakdown(bmr: bmr, tdee: tdee, targets: Macros(kcal: kcal, p: prot, c: carbs, f: fat))
    }

    var dayTargets: Macros {
        manual.on ? manual.macros : computedTargets().targets
    }

    private var carbShare: Double {
        let t = dayTargets
        let cK = t.c * 4, fK = t.f * 9
        return cK + fK > 0 ? cK / (cK + fK) : 0.5
    }

    /// Each meal gets its share of calories and protein; the rest is split between carbs and fat like the day.
    var slotTargets: [SlotTarget] {
        let t = dayTargets
        let sk = slots.reduce(0) { $0 + $1.pk }
        let sp = slots.reduce(0) { $0 + $1.pp }
        let share = carbShare
        var total: [MealType: Int] = [:]
        for s in slots { total[s.type, default: 0] += 1 }
        var seen: [MealType: Int] = [:]
        return slots.map { s in
            let kcal = t.kcal * s.pk / (sk == 0 ? 1 : sk)
            let p = t.p * s.pp / (sp == 0 ? 1 : sp)
            let rest = max(0, kcal - p * 4)
            seen[s.type, default: 0] += 1
            let n = total[s.type] ?? 1
            return SlotTarget(
                id: s.id, type: s.type, name: s.type.label, sub: n > 1 ? "\(seen[s.type]!)/\(n)" : "",
                target: Macros(kcal: kcal.rounded(), p: p.rounded(), c: (rest * share / 4).rounded(), f: (rest * (1 - share) / 9).rounded())
            )
        }
    }

    /// Target for a meal type: average of its slots, or a default share of the day.
    func typeTarget(_ type: MealType) -> Macros {
        let list = slotTargets.filter { $0.type == type }
        if !list.isEmpty {
            return list.reduce(Macros.zero) { $0 + $1.target * (1 / Double(list.count)) }
        }
        let t = dayTargets
        let (pk, pp): (Double, Double) = switch type {
        case .breakfast: (25, 25)
        case .meal: (43, 39)
        case .snack: (14, 22)
        }
        let kcal = t.kcal * pk / 100, p = t.p * pp / 100, rest = max(0, kcal - p * 4)
        return Macros(kcal: kcal, p: p, c: rest * carbShare / 4, f: rest * (1 - carbShare) / 9)
    }

    func scale(for by: NutritionData.AisleBudget.By) -> Double {
        let t = dayTargets, b = NutritionData.base
        switch by {
        case .p: return t.p / b.p
        case .c: return t.c / b.c
        case .f: return t.f / b.f
        case .grams, .kcal: return t.kcal / b.kcal
        }
    }

    /// Likely slot from the time: breakfast in the morning, snack in the afternoon, otherwise lunch or dinner.
    func guessSlot(at date: Date = .now) -> String? {
        let list = slotTargets
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let want: MealType = h < 10.5 ? .breakfast : (h >= 15.5 && h < 18.5 ? .snack : .meal)
        var candidates = list.filter { $0.type == want }
        if candidates.isEmpty { candidates = list.filter { $0.type == .meal } }
        if candidates.isEmpty { candidates = list }
        return (h < 15 ? candidates.first : candidates.last)?.id
    }

    func pref(_ product: Product) -> Int {
        product.foodId.flatMap { prefs[$0] } ?? 0
    }

    func pref(_ food: Food) -> Int { prefs[food.id] ?? 0 }
}

// MARK: - Diet exclusions

private let seafoodPattern = #"seafood|fishes|(^|\s|:)fish|shellfish|crustacean|salmon|shrimp|prawn|mussel|sardine|mackerel|(^|\s|:)cod|saumon|crevette|moule|maquereau|cabillaud|surimi|poisson"#
private let tunaPattern = "tuna|thon"
private let meatPattern = "meats|poultry|chicken|beef|turkey|hams|sausages|poulet|boeuf|bœuf|dinde|jambon|viande|steak|saucisse|lardon|bacon"
private let porkPattern = "pork|hams|bacon|porc|jambon|lardon|saucisson|chorizo"

extension Product {
    /// Categories, allergens and name, to recognize a scanned product.
    var hay: String {
        (categories.joined(separator: " ") + " " + allergens.joined(separator: " ") + " " + name).lowercased()
    }
}

enum DietWord: String {
    case seafood, meat, fish, pork, dairy, egg, animal

    var label: String {
        switch self {
        case .seafood: "produit de la mer"
        case .meat: "viande"
        case .fish: "poisson"
        case .pork: "porc"
        case .dairy: "produit laitier"
        case .egg: "œuf"
        case .animal: "produit animal"
        }
    }
}

extension NutritionSettings {
    func excluded(_ p: Product) -> DietWord? {
        let d = diet, hay = p.hay, al = p.allergens
        // Built-in food: read its tags. Scanned product: categories, allergens and ingredient analysis.
        let tags = p.tags
        let isTuna = tags.map { $0.contains("tuna") } ?? matches(hay, tunaPattern)
        let isSea = tags.map { $0.contains("seafood") }
            ?? ((matches(hay, seafoodPattern) && !matches(hay, tunaPattern)) || al.contains { matches($0, "crustacean|mollusc") })
        let isFish = tags.map { $0.contains("fish") } ?? (isTuna || isSea || al.contains("en:fish"))
        let isMeat = tags.map { $0.contains("meat") } ?? (matches(hay, meatPattern) || matches(hay, porkPattern))
        let isPork = tags.map { $0.contains("pork") } ?? matches(hay, porkPattern)
        let isDairy = tags.map { $0.contains("dairy") } ?? (al.contains("en:milk") || matches(hay, "dairies|cheeses|yogurt|milks"))
        let isEgg = tags.map { $0.contains("egg") } ?? (al.contains("en:eggs") || matches(hay, #"(^|\s|:)eggs"#))
        let nonVegan = p.analysis.contains("en:non-vegan")
        switch d.type {
        case .vegan:
            if isMeat { return .meat }
            if isFish { return .fish }
            if isDairy { return .dairy }
            if isEgg { return .egg }
            if nonVegan { return .animal }
        case .veg:
            if isMeat { return .meat }
            if isFish { return .fish }
        case .pesc:
            if isMeat { return .meat }
        case .nopork:
            if isPork { return .pork }
        case .omni:
            break
        }
        if d.seafood && (isSea || (isFish && !(d.tuna && isTuna))) { return .seafood }
        return nil
    }

    func excluded(_ food: Food) -> DietWord? { excluded(Product(food: food)) }

    func allowed(_ food: Food?) -> Bool {
        guard let food else { return false }
        return excluded(food) == nil && pref(food) != -1
    }
}

// MARK: - Score

struct ScoreReason: Hashable {
    var text: String
    var bad = false
}

struct NutritionScore {
    var value: Int
    var excludedBy: DietWord?
    var reasons: [ScoreReason]

    var grade: Grade { Grade(value) }
}

enum Grade: String {
    case A, B, C, D, E

    init(_ s: Int) {
        switch s {
        case 80...: self = .A
        case 65..<80: self = .B
        case 45..<65: self = .C
        case 25..<45: self = .D
        default: self = .E
        }
    }

    var verdict: String {
        switch self {
        case .A: "Excellent pour toi"
        case .B: "Bon choix"
        case .C: "Correct, avec modération"
        case .D: "Pas idéal pour ton objectif"
        case .E: "À éviter"
        }
    }
}

extension NutritionSettings {
    func score(_ p: Product) -> NutritionScore {
        if let ex = excluded(p) {
            return NutritionScore(value: 5, excludedBy: ex, reasons: [ScoreReason(text: "Exclu par tes réglages : \(ex.label)", bad: true)])
        }
        var result = rawScore(p)
        if pref(p) == -1 {
            result.reasons = Array(([ScoreReason(text: "Tu n'aimes pas cet aliment", bad: true)] + result.reasons).prefix(4))
        }
        return result
    }

    func score(_ food: Food) -> NutritionScore { score(Product(food: food)) }

    private func rawScore(_ p: Product) -> NutritionScore {
        let n = p.n, kcal = max(n.kcal, 1)
        var reasons: [ScoreReason] = []
        var s = 50.0
        let pShare = n.p * 4 / kcal
        s += min(30, pShare * 75)
        if pShare >= 0.3 {
            reasons.append(ScoreReason(text: "Riche en protéines (\(Int(min(100, pShare * 100).rounded())) % des calories)"))
        } else if pShare < 0.08 && n.kcal > 150 && ![.feculents, .graisses, .fruits, .legumes].contains(p.fam) {
            s -= 8
            reasons.append(ScoreReason(text: "Presque pas de protéines pour beaucoup de calories", bad: true))
        }
        let fiber = n.fiber ?? 0
        if fiber >= 5 {
            s += 8
            reasons.append(ScoreReason(text: "Bonne source de fibres (\(NutritionFormat.number(fiber)) g)"))
        } else if fiber >= 3 { s += 4 }
        let sugar = n.sugar ?? 0
        let natural = [.fruits, .laitiers, .legumes].contains(p.fam) && sugar <= 15
        if !natural && sugar > 5 {
            s -= min(28, (sugar - 5) * 1.2)
            reasons.append(ScoreReason(text: "\(sugar >= 12 ? "Très sucré" : "Sucré") (\(NutritionFormat.number(sugar)) g pour 100 g)", bad: true))
        }
        let sat = n.sat ?? 0, satLimit: Double = p.fam == .graisses ? 18 : 4
        if sat > satLimit {
            s -= min(15, (sat - satLimit) * 1.2)
            if sat >= 8 && p.fam != .graisses {
                reasons.append(ScoreReason(text: "Riche en graisses saturées (\(NutritionFormat.number(sat)) g)", bad: true))
            }
        }
        let salt = n.salt ?? 0
        if salt > 1.2 {
            s -= min(15, (salt - 1.2) * 6)
            if salt >= 1.5 { reasons.append(ScoreReason(text: "Salé (\(NutritionFormat.number(salt)) g de sel pour 100 g)", bad: true)) }
        }
        switch p.nova {
        case 1:
            s += 12
            reasons.append(ScoreReason(text: "Aliment brut, pas transformé"))
        case 2: s += 6
        case 4:
            s -= 12
            reasons.append(ScoreReason(text: "Ultra-transformé", bad: true))
        default: break
        }
        if p.additives >= 4 {
            s -= 5
            reasons.append(ScoreReason(text: "\(p.additives) additifs", bad: true))
        }
        if n.kcal >= 400 && pShare < 0.15 && fiber < 5 && p.fam != .graisses && p.fam != .feculents {
            s -= 10
            reasons.append(ScoreReason(text: "Très calorique (\(Int(n.kcal.rounded())) kcal pour 100 g) et peu rassasiant", bad: true))
        }
        if p.fam == .graisses { reasons.append(ScoreReason(text: "Très calorique : à doser à la cuillère", bad: true)) }
        let value = Int(max(0, min(100, s.rounded())))
        let sorted = reasons.filter { !$0.bad } + reasons.filter(\.bad)
        return NutritionScore(value: value, excludedBy: nil, reasons: Array(sorted.prefix(4)))
    }
}

// MARK: - Aisle of a scanned product

extension Product {
    var guessedAisle: Aisle {
        let hay = hay, sugar = n.sugar ?? 0
        if matches(hay, "alcoholic|beers|wines|spirits|sodas|soft-drinks|sweetened-beverages|energy-drinks|confectioner|chocolate|candies|biscuits|cookies|cakes|pastries|ice-cream|sweet-snacks|salty-snacks|crisps|desserts|pizzas|bonbon|gâteau|biscuit|chips|soda") {
            if matches(hay, "greek|skyr|fromage-blanc|cottage") && sugar < 6 { return .laitiers }
            return .extras
        }
        if matches(hay, tunaPattern) { return .viandes }
        if matches(hay, "protein-powder|whey|dietary-supplement|protéine en poudre") { return .poudre }
        if matches(hay, #"(^|\s|:)eggs|œuf|oeuf"#) { return .oeufs }
        if matches(hay, "yogurt|yoghurt|skyr|fromages-blancs|fromage blanc|cottage|quark|(^|:)milks|lait ") { return sugar > 9 ? .extras : .laitiers }
        if matches(hay, "cheeses|fromage|mozzarella|parmesan|emmental|cheddar") { return .fromages }
        if matches(hay, meatPattern) || matches(hay, porkPattern) || matches(hay, "tofu|tempeh|seitan") { return .viandes }
        if matches(hay, "olive-oils|vegetable-oils|(^|:)fats|butters|nuts|peanut|almond|huile|beurre|amande|cacahu|noix|avocado") { return .graisses }
        if matches(hay, "sauces|condiments|mustards|ketchup|spices|salsa|sauce|moutarde|épice") { return .sauces }
        if matches(hay, "breakfast-cereals") && sugar > 12 { return .extras }
        if matches(hay, #"fruit-juices|nectars|compotes|(^|\s)jus"#) { return .extras }
        if matches(hay, "rices|pastas|potatoes|breads|oat|cereals|couscous|semolin|quinoa|legumes|lentil|tortilla|wraps|riz|pâtes|pates|pomme de terre|patate|pain|avoine|semoule|lentille") { return .feculents }
        if matches(hay, "vegetables|légume|legume") { return .legumes }
        if matches(hay, "fruits|banane|kiwi") { return .fruits }
        let kp = n.p * 4, kc = n.c * 4, kf = n.f * 9
        if sugar > 15 || (kf > kp && kf > kc && n.p < 10 && n.kcal > 350) { return .extras }
        if kp >= kc && kp >= kf && n.p >= 15 { return .viandes }
        if kc >= kp && kc >= kf { return .feculents }
        if kf >= kp && kf >= kc { return .graisses }
        return .extras
    }
}

// MARK: - Weekly quantity

struct WeeklyQuantity {
    var grams: Double
    var count: Int
    var explanation: String
}

extension NutritionSettings {
    func aisleBudget(_ fam: Aisle) -> Double {
        guard let b = NutritionData.budgets[fam] else { return 0 }
        return b.budget * scale(for: b.by)
    }

    func weeklyQuantity(_ p: Product, aisle fam: Aisle, variety: [Aisle: Int]) -> WeeklyQuantity {
        guard let b = NutritionData.budgets[fam] else { return WeeklyQuantity(grams: 0, count: 1, explanation: "") }
        let count = max(1, variety[fam] ?? b.count)
        let budget = aisleBudget(fam), share = budget / Double(count)
        if fam == .extras {
            let g = p.n.kcal > 0 ? share / p.n.kcal * 100 : 0
            let week = Int((budget / 50).rounded()) * 50
            return WeeklyQuantity(grams: g, count: count,
                                  explanation: "Pas prévu dans ton plan. Si tu en prends, reste sous \(week) kcal pour la semaine, soit environ \(week / 7) kcal par jour.")
        }
        let g: Double
        let total: String
        switch b.by {
        case .grams:
            g = share
            total = "\(NutritionFormat.weight(budget)) de \(fam.label.lowercased()) par semaine"
        default:
            let per: Double = switch b.by {
            case .p: p.n.p
            case .c: p.n.c
            case .f: p.n.f
            default: p.n.kcal
            }
            g = per > 0 ? share / per * 100 : share
            let macro = switch b.by {
            case .p: "protéines"
            case .c: "glucides"
            default: "lipides"
            }
            total = "\(Int(budget.rounded())) g de \(macro) par semaine venant de ce rayon"
        }
        let also = fam.examples.map { " (\($0))" } ?? ""
        let explanation = count > 1
            ? "Ton plan prévoit \(total). Je les répartis sur \(count) produits différents\(also), donc celui-ci en couvre 1/\(count)."
            : "Ton plan prévoit \(total), couverts entièrement par ce produit."
        return WeeklyQuantity(grams: g, count: count, explanation: explanation)
    }
}

// MARK: - Portion solver

enum PortionSolver {
    /// Weighted least squares with grams ≥ 0: the products add up to the meal's remaining
    /// calories, protein (counted double), carbs and fat. Fixed quantities are taken out first;
    /// products counted by the unit (eggs, spoons) are rounded, then the rest is solved around them.
    static func solve(_ items: [Product], target: Macros, rounded: Bool = false) -> [Double] {
        let keys = MacroKey.allCases
        let weight: [MacroKey: Double] = [.kcal: 1, .p: 2, .c: 1, .f: 1]
        var goal = target
        for it in items { if let fixed = it.fixed { goal = goal - it.n.macros * (fixed / 100) } }
        let free = items.indices.filter { items[$0].fixed == nil }
        var scale: [MacroKey: Double] = [:]
        for k in keys { scale[k] = max(abs(target[k]), k == .kcal ? 100 : 5) }
        let a = free.map { i in keys.map { k in items[i].n.macros[k] / 100 * weight[k]!.squareRoot() / scale[k]! } }
        let b = keys.map { k in goal[k] * weight[k]!.squareRoot() / scale[k]! }
        var g = Array(repeating: 0.0, count: free.count)
        for _ in 0..<4000 {
            var moved = 0.0
            for j in g.indices {
                var num = 0.0, den = 1e-6
                for m in 0..<4 {
                    var others = 0.0
                    for q in g.indices where q != j { others += a[q][m] * g[q] }
                    num += a[j][m] * (b[m] - others)
                    den += a[j][m] * a[j][m]
                }
                let next = min(NutritionData.maxGrams, max(0, num / den))
                moved = max(moved, abs(next - g[j]))
                g[j] = next
            }
            if moved < 0.01 { break }
        }
        let units = free.filter { items[$0].unit != nil }
        if !units.isEmpty && units.count < free.count && !rounded {
            var fixedItems = items
            for (j, i) in free.enumerated() where items[i].unit != nil {
                fixedItems[i].fixed = roundDose(g[j], items[i])
            }
            return solve(fixedItems, target: target, rounded: true)
        }
        var out = items.map { $0.fixed ?? 0 }
        for (j, i) in free.enumerated() { out[i] = roundDose(g[j], items[i]) }
        return out
    }

    static func roundDose(_ g: Double, _ it: Product) -> Double {
        if let unit = it.unit { return (g / unit.step).rounded() * unit.step }
        return g >= 100 ? (g / 5).rounded() * 5 : g.rounded()
    }

    static func totals(_ items: [Product], grams: [Double]) -> Macros {
        zip(items, grams).reduce(Macros.zero) { $0 + $1.0.n.macros * ($1.1 / 100) }
    }
}

// MARK: - Weight trend

enum WeightTrend {
    /// Average of the weigh-ins between `from` and `to` days ago.
    static func average(_ weights: [String: Double], from: Int, to: Int) -> (count: Int, avg: Double?) {
        let values = (from...to).compactMap { weights[DayKey.offset($0)] }
        return (values.count, values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
    }
}

extension NutritionSettings {
    /// Once a week, compares the last 7 days' average weight with the 7 before, and moves
    /// calories by 100 kcal when the trend strays from the goal. Returns true when it changed something.
    mutating func checkAdjustment(weights: [String: Double]) -> Bool {
        let offset = NutritionData.goalOffsets[min(max(profile.goal, 0), 4)]
        if manual.on || offset == 0 { return false }
        let today = DayKey.today
        if let last = adj.last, DayKey.daysBetween(last, today) < 7 { return false }
        let now = WeightTrend.average(weights, from: 0, to: 6), prev = WeightTrend.average(weights, from: 7, to: 13)
        guard now.count >= 3, prev.count >= 3, let nowAvg = now.avg, let prevAvg = prev.avg else { return false }
        let change = nowAvg - prevAvg, expected = offset * 7 / 7700
        profile.weight = (nowAvg * 10).rounded() / 10
        var step = 0.0
        var message = "Tu es dans le bon rythme, on ne touche à rien."
        if expected < 0 {
            if change > expected * 0.3 {
                step = -100
                message = "Ta moyenne stagne : j'ai baissé tes calories de 100 kcal par jour."
            } else if change < expected * 1.6 && change < -0.01 * nowAvg {
                step = 100
                message = "Tu perds trop vite : j'ai remonté tes calories de 100 kcal par jour pour protéger tes muscles."
            }
        } else {
            if change < expected * 0.3 {
                step = 100
                message = "Ta prise est trop lente : +100 kcal par jour."
            } else if change > expected * 2 {
                step = -100
                message = "Ta prise est trop rapide : −100 kcal par jour."
            }
        }
        if step < 0 {
            let c = computedTargets()
            if c.targets.kcal + step < max(c.bmr, profile.sex == .f ? 1200 : 1500) {
                step = 0
                message = "Ta moyenne stagne, mais je ne descends pas plus bas en calories : bouge un peu plus (pas, marche inclinée)."
            }
        }
        adj.kcal += step
        adj.last = today
        adj.message = message
        return true
    }
}

// MARK: - Grocery list matching

private let stopWords: Set<String> = [
    "de", "du", "des", "la", "le", "les", "au", "aux", "et", "en", "sans", "nature", "crue", "crues", "cru", "conserve",
    "seche", "seches", "egoutte", "surgele", "surgeles", "surgelees", "with", "and", "raw", "dry", "canned", "frozen", "plain",
]

func normalized(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
}

private func significantWords(_ s: String) -> [String] {
    normalized(s)
        .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 3 && !stopWords.contains($0) && Int($0) == nil }
}

extension NutritionSettings {
    /// The open row of the list that matches a scanned product (name words and aisle).
    func matchRow(_ p: Product, in list: [ShopRow]) -> Int? {
        if excluded(p) != nil { return nil }
        let hay = " " + normalized(p.name + " " + p.categories.joined(separator: " "))
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression) + " "
        var best: Int?, bestScore = 0.0
        for (i, row) in list.enumerated() where !row.done {
            let words = Set(significantWords(row.title))
            let hits = words.filter { hay.contains(" " + $0) || hay.contains(" " + $0.replacingOccurrences(of: "s$", with: "", options: .regularExpression)) }.count
            guard hits > 0 else { continue }
            let s = Double(hits) + (row.fam == p.fam ? 1.5 : 0)
            if s > bestScore && (row.fam == p.fam || hits >= 2) {
                bestScore = s
                best = i
            }
        }
        return best
    }

    func pricePerKg(_ row: ShopRow) -> Double {
        if let ppk = row.ppk { return ppk }
        if let id = row.ref?.foodId, let index = Int(id.dropFirst(4)), let price = NutritionData.foodPrice[index] { return price }
        return NutritionData.aislePrice[row.fam] ?? 6
    }

    func need(_ row: ShopRow, variety: [Aisle: Int]) -> Double {
        if let fixed = row.fixedG { return fixed }
        if let ref = row.ref { return weeklyQuantity(ref, aisle: row.fam, variety: variety).grams }
        return row.g ?? 0
    }
}

// MARK: - Recipes

struct RecipeIngredient: Identifiable {
    var part: Int
    var role: RecipePart.Role
    var food: Food
    var grams: Double
    var id: Int { part }
}

struct BuiltRecipe {
    var template: RecipeTemplate
    var picks: [String?]
    var items: [RecipeIngredient]
    var totals: Macros
    var steps: String
}

extension NutritionSettings {
    /// Foods for a part: the recipe's own options first, otherwise a liked food from the same aisle.
    func choices(for part: RecipePart) -> [Food] {
        let options = part.options.compactMap { NutritionData.food($0) }.filter { allowed($0) }
        if !options.isEmpty { return options }
        if part.role == .X { return [] }
        guard let fam = NutritionData.food(part.options.first)?.fam else { return [] }
        let same = NutritionData.foods.filter { $0.fam == fam && allowed($0) && $0.fam != .extras }
        let liked = same.filter { pref($0) == 1 }
        return liked.isEmpty ? same : liked
    }

    private func pickWeighted(_ list: [Food]) -> Food? {
        let w = list.map { pref($0) == 1 ? 3.0 : 1.0 }
        var x = Double.random(in: 0..<max(w.reduce(0, +), 0.0001))
        for (i, food) in list.enumerated() {
            x -= w[i]
            if x <= 0 { return food }
        }
        return list.last
    }

    func pickParts(_ tpl: RecipeTemplate, keep: [String?] = []) -> [String?] {
        tpl.parts.enumerated().map { i, part in
            let ch = choices(for: part)
            if i < keep.count, let kept = keep[i], ch.contains(where: { $0.id == kept }) { return kept }
            return pickWeighted(ch)?.id
        }
    }

    func isValid(_ tpl: RecipeTemplate) -> Bool {
        tpl.parts.allSatisfy { $0.role == .X || !choices(for: $0).isEmpty }
    }

    func likes(_ tpl: RecipeTemplate) -> Int {
        tpl.parts.filter { $0.options.contains { NutritionData.food($0).map { pref($0) } == 1 } }.count
    }

    func pool(for type: MealType, styles: [String]) -> [RecipeTemplate] {
        // Vegetarian recipes only show up for a meat eater who likes their protein
        let vegDiet = diet.type == .veg || diet.type == .vegan
        return NutritionData.recipes.filter { r in
            r.kinds.contains(type) && isValid(r)
                && (styles.isEmpty || styles.contains { r.tags.contains($0) })
                && (!r.veg || vegDiet || r.parts[0].options.contains { NutritionData.food($0).map { pref($0) } == 1 })
        }
    }

    func build(_ pick: RecipePick, target: Macros) -> BuiltRecipe? {
        guard let tpl = NutritionData.recipe(pick.tpl) else { return nil }
        let picks = pickParts(tpl, keep: pick.picks)
        var products: [Product] = []
        var parts: [(Int, RecipePart.Role, Food)] = []
        for (i, part) in tpl.parts.enumerated() {
            guard let food = NutritionData.food(picks[i]) else { continue }
            var product = Product(food: food)
            let solved = part.role == .P || part.role == .C || part.role == .F
            product.fixed = solved ? nil : (part.grams ?? ((part.role == .V || part.role == .R) ? 100 : nil))
            products.append(product)
            parts.append((i, part.role, food))
        }
        let grams = PortionSolver.solve(products, target: target)
        let items = parts.enumerated().map { j, p in RecipeIngredient(part: p.0, role: p.1, food: p.2, grams: grams[j]) }
        let totals = items.reduce(Macros.zero) { $0 + $1.food.n.macros * ($1.grams / 100) }
        func names(_ role: RecipePart.Role) -> String {
            let list = items.filter { $0.role == role && $0.grams > 0 }.map { $0.food.shortName.lowercased() }
            if list.isEmpty && role == .F { return "une poêle antiadhésive" }
            guard let last = list.last else { return "" }
            return list.count > 1 ? list.dropLast().joined(separator: ", ") + " et " + last : last
        }
        var steps = tpl.steps
        for role in [RecipePart.Role.P, .C, .F, .V, .R, .X] {
            steps = steps.replacingOccurrences(of: "{\(role.rawValue)}", with: names(role))
        }
        return BuiltRecipe(template: tpl, picks: picks, items: items, totals: totals, steps: steps)
    }
}

// MARK: - Stats

struct DayStat: Identifiable {
    var day: String
    var logged: Bool
    var macros: Macros
    var weight: Double?
    var id: String { day }

    var date: Date { DayKey.date(day) ?? .now }

    /// Calories between 90 and 105 % of the target, and protein at least 90 %.
    func onTarget(_ t: Macros) -> Bool {
        logged && macros.kcal >= t.kcal * 0.9 && macros.kcal <= t.kcal * 1.05 && macros.p >= t.p * 0.9
    }
}

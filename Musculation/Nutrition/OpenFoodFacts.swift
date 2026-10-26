import Foundation

/// Product lookup on Open Food Facts by barcode.
enum OpenFoodFacts {
    enum LookupError: LocalizedError {
        case notFound
        case noValues(String)
        case offline

        var errorDescription: String? {
            switch self {
            case .notFound: "Ce produit n'est pas dans Open Food Facts. Choisis un aliment proche dans la liste."
            case .noValues(let name): "\(name) : pas de valeurs nutritionnelles dans Open Food Facts."
            case .offline: "Pas de connexion à Open Food Facts. Vérifie ton réseau et réessaie."
            }
        }
    }

    private struct Response: Decodable {
        var status: Int?
        var product: OFFProduct?
    }

    private struct OFFProduct: Decodable {
        var product_name: String?
        var product_name_fr: String?
        var brands: String?
        var nutriments: [String: FlexibleNumber]?
        var image_front_small_url: String?
        var nova_group: FlexibleNumber?
        var additives_n: FlexibleNumber?
        var categories_tags: [String]?
        var allergens_tags: [String]?
        var ingredients_analysis_tags: [String]?
        var product_quantity: FlexibleNumber?
    }

    /// Open Food Facts returns numbers either as numbers or as strings.
    private struct FlexibleNumber: Decodable {
        var value: Double?

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d }
            else if let s = try? c.decode(String.self) { value = Double(s.replacingOccurrences(of: ",", with: ".")) }
            else { value = nil }
        }
    }

    static func product(code raw: String) async throws -> Product {
        let code = raw.filter(\.isNumber)
        guard !code.isEmpty else { throw LookupError.notFound }
        let fields = "product_name,product_name_fr,brands,nutriments,image_front_small_url,nova_group,additives_n,categories_tags,allergens_tags,ingredients_analysis_tags,product_quantity"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)") else {
            throw LookupError.notFound
        }
        var request = URLRequest(url: url)
        request.setValue("Musculation iOS - nutrition", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw LookupError.offline
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw LookupError.notFound }
        let p = response.product
        let nu = p?.nutriments ?? [:]
        let kcal = nu["energy-kcal_100g"]?.value ?? nu["energy_100g"]?.value.map { $0 / 4.184 }
        let name = p?.product_name_fr ?? p?.product_name ?? ""
        guard response.status == 1, let p, let kcal else {
            throw name.isEmpty ? LookupError.notFound : LookupError.noValues(name)
        }
        let n = Nutrients(
            kcal: kcal,
            p: nu["proteins_100g"]?.value ?? 0,
            c: nu["carbohydrates_100g"]?.value ?? 0,
            f: nu["fat_100g"]?.value ?? 0,
            sugar: nu["sugars_100g"]?.value ?? 0,
            sat: nu["saturated-fat_100g"]?.value ?? 0,
            salt: nu["salt_100g"]?.value ?? 0,
            fiber: nu["fiber_100g"]?.value ?? 0
        )
        var product = Product(
            code: code,
            name: name.isEmpty ? "Produit sans nom" : name,
            brand: (p.brands ?? "").split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "",
            imageURL: p.image_front_small_url ?? "",
            nova: p.nova_group?.value.map { Int($0) },
            additives: Int(p.additives_n?.value ?? 0),
            categories: p.categories_tags ?? [],
            allergens: p.allergens_tags ?? [],
            analysis: p.ingredients_analysis_tags ?? [],
            packG: p.product_quantity?.value ?? 0,
            n: n
        )
        product.fam = product.guessedAisle
        return product
    }
}

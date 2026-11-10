import Foundation
import Security

struct Nutrition: Codable, Hashable {
    var sourceID: Int
    var description: String
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
}
struct Grocery: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var quantity: String
    var category: String
    var nutrition: Nutrition?
    var expiry: Date?
    var inStock: Bool?
    var available: Bool { inStock != false && (expiry.map { Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: .now) } ?? true) }
}
struct Ingredient: Codable, Hashable, Identifiable {
    var name: String
    var amount: String
    var id: String { name + amount }
}
struct Recipe: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var ingredients: [Ingredient]
    var instructions: String
    var source: String
    var image: String?
    var containsEgg: Bool { ingredients.contains { IngredientRules.containsEgg($0.name) } }
    var mainIngredient: String { ingredients.first?.name.capitalized ?? "Vegetables" }
}
struct ShoppingItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: String
    var purchased = false
    var estimatedCost: Double?
}
struct UserProfile: Codable, Hashable {
    var name = ""
    var householdSize = 1
    var preferredIngredients = ""
    var preferredCuisines = ""
    var dislikes = ""
    var avoidIngredients = ""
    var allergens: [String] = []
    var dairyFree = false
    var weeklyBudget: Double?
    var maxCookingMinutes: Int?
    var equipment = ""
    var cookingConfidence = "Learning"
}
struct RecipeDetails: Codable, Hashable {
    var baseServings: Int?
    var minutes: Int?
    var cuisine = ""
    var equipment = ""
    var estimatedCost: Double?
}
struct PlannedMeal: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var slot: String
    var recipeID: String
    var servings: Int
    var completed = false
}
struct MealEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var recipeID: String
    var title: String
    var mainIngredient: String
    var servings: Int
}
struct PantryData: Codable {
    var groceries: [Grocery] = []
    var shopping: [ShoppingItem] = []
    var recipes: [Recipe] = []
    var excludeEggs = false
    var profile = UserProfile()
    var plans: [PlannedMeal] = []
    var history: [MealEvent] = []
    var favourites: [String] = []
    var ratings: [String: Int] = [:]
    var recipeDetails: [String: RecipeDetails] = [:]
    var planApproved = false
    var planningStart = Calendar.current.startOfDay(for: .now)
    var planningMealCount = 7
    init(groceries: [Grocery] = [], shopping: [ShoppingItem] = [], recipes: [Recipe] = [], excludeEggs: Bool = false) {
        self.groceries = groceries; self.shopping = shopping; self.recipes = recipes; self.excludeEggs = excludeEggs
    }
    enum CodingKeys: String, CodingKey {
        case groceries, shopping, recipes, excludeEggs, profile, plans, history, favourites, ratings, recipeDetails, planApproved, planningStart, planningMealCount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groceries = try c.decodeIfPresent([Grocery].self, forKey: .groceries) ?? []
        shopping = try c.decodeIfPresent([ShoppingItem].self, forKey: .shopping) ?? []
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        excludeEggs = try c.decodeIfPresent(Bool.self, forKey: .excludeEggs) ?? false
        profile = try c.decodeIfPresent(UserProfile.self, forKey: .profile) ?? UserProfile()
        plans = try c.decodeIfPresent([PlannedMeal].self, forKey: .plans) ?? []
        history = try c.decodeIfPresent([MealEvent].self, forKey: .history) ?? []
        favourites = try c.decodeIfPresent([String].self, forKey: .favourites) ?? []
        ratings = try c.decodeIfPresent([String: Int].self, forKey: .ratings) ?? [:]
        recipeDetails = try c.decodeIfPresent([String: RecipeDetails].self, forKey: .recipeDetails) ?? [:]
        planApproved = try c.decodeIfPresent(Bool.self, forKey: .planApproved) ?? false
        planningStart = try c.decodeIfPresent(Date.self, forKey: .planningStart) ?? Calendar.current.startOfDay(for: .now)
        planningMealCount = try c.decodeIfPresent(Int.self, forKey: .planningMealCount) ?? 7
    }
}

enum PantryDisk {
    static var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("pantry.json") }
    static func read() throws -> PantryData {
        guard FileManager.default.fileExists(atPath: url.path) else { var d = PantryData(); d.recipes = seedRecipes(); return d }
        var d = try JSONDecoder().decode(PantryData.self, from: Data(contentsOf: url))
        let known = Set(d.recipes.map(\.id))
        d.recipes.append(contentsOf: seedRecipes().filter { !known.contains($0.id) })
        return d
    }
    static func seedRecipes() -> [Recipe] {
        guard let url = Bundle.main.url(forResource: "SeedRecipes", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Recipe].self, from: data)) ?? []
    }
    static func write(_ value: PantryData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the previous successful save for recovery; never overwrite unreadable data on startup.
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = url.appendingPathExtension("previous")
            try? FileManager.default.removeItem(at: previous)
            try FileManager.default.copyItem(at: url, to: previous)
        }
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    static func updateWidget(_ value: PantryData) throws {
        var snapshot = value
        snapshot.recipes = Array(RecommendationEngine.rank(value).prefix(1))
        snapshot.history = []; snapshot.plans = []; snapshot.recipeDetails = [:]; snapshot.ratings = [:]
        snapshot.shopping = value.shopping.filter { !$0.purchased }
        snapshot.profile = UserProfile()
        try WidgetSnapshot.write(try JSONEncoder().encode(snapshot))
    }
}
enum WidgetSnapshot {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "SharedAccessGroup") as? String ?? "" }
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "GreenPantryWidget", kSecAttrAccount as String: "snapshot", kSecAttrAccessGroup as String: group] }
    static func read() -> PantryData {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return PantryData() }
        return (try? JSONDecoder().decode(PantryData.self, from: data)) ?? PantryData()
    }
    static func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

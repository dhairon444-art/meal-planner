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
}
struct ShoppingItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: String
    var purchased = false
}
struct PantryData: Codable {
    var groceries: [Grocery] = []
    var shopping: [ShoppingItem] = []
    var recipes: [Recipe] = []
    var excludeEggs = false
}

enum PantryDisk {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("pantry.json")
    }
    static func read() -> PantryData {
        guard let data = try? Data(contentsOf: url), var saved = try? JSONDecoder().decode(PantryData.self, from: data) else {
            var initial = PantryData(); initial.recipes = seedRecipes(); return initial
        }
        if saved.recipes.isEmpty { saved.recipes = seedRecipes() }
        return saved
    }
    static func seedRecipes() -> [Recipe] {
        guard let url = Bundle.main.url(forResource: "SeedRecipes", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Recipe].self, from: data)) ?? []
    }
    static func write(_ value: PantryData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        // Widgets need only a small read-only snapshot, not the full recipe database.
        var snapshot = value
        snapshot.recipes = Array(value.recipes.filter { !value.excludeEggs || !$0.containsEgg }.sorted {
            IngredientRules.missing($0, in: value.groceries).count < IngredientRules.missing($1, in: value.groceries).count
        }.prefix(1))
        snapshot.shopping = value.shopping.filter { !$0.purchased }
        try WidgetSnapshot.write(try JSONEncoder().encode(snapshot))
    }
}

enum WidgetSnapshot {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "SharedAccessGroup") as? String ?? "" }
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "GreenPantryWidget", kSecAttrAccount as String: "snapshot", kSecAttrAccessGroup as String: group]
    }
    static func read() -> PantryData {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return PantryData() }
        return (try? JSONDecoder().decode(PantryData.self, from: data)) ?? PantryData()
    }
    static func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Pantry saved, but the widget snapshot could not update (\(status))."]) }
    }
}

enum IngredientRules {
    static func containsEgg(_ input: String) -> Bool {
        let words = input.lowercased().components(separatedBy: CharacterSet.letters.inverted)
        return words.contains("egg") || words.contains("eggs")
    }
    static func key(_ input: String) -> String {
        let text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = ["tomatoes":"tomato", "potatoes":"potato", "chickpeas":"chickpea", "garbanzo beans":"chickpea", "aubergine":"eggplant", "courgette":"zucchini", "bell pepper":"capsicum", "scallions":"spring onion", "yogurt":"yoghurt", "eggs":"egg", "onions":"onion", "garlic cloves":"garlic", "lentils":"lentil"]
        return aliases[text] ?? text
    }
    static func has(_ name: String, in groceries: [Grocery]) -> Bool {
        groceries.contains { key($0.name) == key(name) }
    }
    static func missing(_ recipe: Recipe, in groceries: [Grocery]) -> [Ingredient] {
        recipe.ingredients.filter { !has($0.name, in: groceries) }
    }
    // Conservative checks supplement the provider's Vegetarian category; they cannot certify dietary labels.
    static func isVegetarian(_ text: String) -> Bool {
        let words = text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let excluded: Set<String> = ["chicken", "beef", "pork", "bacon", "ham", "lamb", "fish", "prawn", "prawns", "shrimp", "anchovy", "anchovies", "tuna", "salmon", "gelatin", "gelatine", "lard", "oyster", "worcestershire", "seafood", "turkey", "sausage", "sausages", "meat", "venison", "duck", "crab", "lobster", "mussels", "squid", "octopus", "scallops", "prosciutto", "chorizo", "salami", "pepperoni", "veal", "mutton", "suet"]
        return Set(words).isDisjoint(with: excluded)
    }
}

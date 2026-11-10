import Foundation

struct FoodAmount: Equatable {
    var value: Double
    var unit: String
    var dimension: String { ["g": "mass", "ml": "volume", "": "count"][unit] ?? unit }
    var text: String { "\(Self.number(value))\(unit.isEmpty ? "" : " " + unit)" }
    static func number(_ n: Double) -> String { n.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...6))) }
    static func parse(_ raw: String) -> FoodAmount? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for (symbol, fraction) in ["½":" 1/2", "¼":" 1/4", "¾":" 3/4", "⅓":" 1/3", "⅔":" 2/3", "⅛":" 1/8"] { text = text.replacingOccurrences(of: symbol, with: fraction) }
        // Accept only known units; package counts never silently become weights.
        let pattern = #"^\s*(\d+(?:\.\d+)?(?:\s+\d+/\d+)?|\d+/\d+)\s*([a-z]*)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let nr = Range(match.range(at: 1), in: text), let ur = Range(match.range(at: 2), in: text) else { return nil }
        func numeric(_ s: String) -> Double? {
            if s.contains("/") { let p = s.split(separator: "/").compactMap { Double($0) }; guard p.count == 2, p[1] != 0 else { return nil }; return p[0] / p[1] }
            return Double(s)
        }
        let pieces = text[nr].split(separator: " ").map(String.init)
        let numbers = pieces.compactMap(numeric)
        guard numbers.count == pieces.count else { return nil }
        let value = numbers.reduce(0,+)
        let unit = String(text[ur])
        let conversions: [String: (String, Double)] = ["":("",1), "g":("g",1), "gram":("g",1), "grams":("g",1), "gms":("g",1), "kg":("g",1000), "mg":("g",0.001), "ml":("ml",1), "l":("ml",1000), "litre":("ml",1000), "litres":("ml",1000), "tsp":("ml",5), "teaspoon":("ml",5), "teaspoons":("ml",5), "tbsp":("ml",15), "tablespoon":("ml",15), "tablespoons":("ml",15), "cup":("ml",240), "cups":("ml",240), "oz":("g",28.3495), "lb":("g",453.592), "clove":("clove",1), "cloves":("clove",1), "tin":("tin",1), "tins":("tin",1), "can":("tin",1), "cans":("tin",1), "piece":("",1), "pieces":("",1), "item":("",1), "items":("",1)]
        guard let c = conversions[unit], value.isFinite, value >= 0 else { return nil }
        return FoodAmount(value: value * c.1, unit: c.0)
    }
    static func scaled(_ raw: String, by factor: Double) -> String {
        guard factor != 1 else { return raw }
        guard var q = parse(raw) else { return raw.isEmpty ? "Amount not specified" : "\(raw) (×\(number(factor)))" }
        q.value *= factor; return q.text
    }
}
enum IngredientRules {
    static func words(_ input: String) -> [String] { input.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty } }
    static func containsEgg(_ input: String) -> Bool { words(input).contains { $0 == "egg" || $0 == "eggs" } }
    static func key(_ input: String) -> String {
        let text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = ["tomatoes":"tomato", "potatoes":"potato", "chickpeas":"chickpea", "garbanzo beans":"chickpea", "aubergine":"eggplant", "courgette":"zucchini", "bell pepper":"capsicum", "scallions":"spring onion", "yogurt":"yoghurt", "eggs":"egg", "onions":"onion", "garlic cloves":"garlic", "lentils":"lentil", "fresh coriander":"coriander", "cilantro":"coriander"]
        return aliases[text] ?? text
    }
    static func has(_ name: String, in groceries: [Grocery]) -> Bool { groceries.contains { $0.available && key($0.name) == key(name) && (FoodAmount.parse($0.quantity)?.value ?? 1) > 0 } }
    static func missing(_ recipe: Recipe, in groceries: [Grocery]) -> [Ingredient] { recipe.ingredients.filter { !has($0.name, in: groceries) } }
    static func isVegetarian(_ text: String) -> Bool {
        let excluded: Set<String> = ["chicken", "beef", "pork", "bacon", "ham", "lamb", "fish", "prawn", "prawns", "shrimp", "anchovy", "anchovies", "tuna", "salmon", "gelatin", "gelatine", "lard", "oyster", "worcestershire", "seafood", "turkey", "sausage", "sausages", "meat", "venison", "duck", "crab", "lobster", "mussels", "squid", "octopus", "scallops", "prosciutto", "chorizo", "salami", "pepperoni", "veal", "mutton", "suet"]
        return Set(words(text)).isDisjoint(with: excluded)
    }
    static let allergyNames = ["Eggs", "Dairy", "Peanuts", "Tree nuts", "Soy", "Sesame", "Gluten"]
    static func conflicts(_ name: String, profile: UserProfile, excludeEggs: Bool) -> Bool {
        let tokens = Set(words(name)); let normalized = key(name)
        let dairy = ["milk", "cheese", "yoghurt", "yogurt", "paneer", "butter", "cream", "ghee", "parmesan", "mozzarella", "feta", "cheddar", "halloumi", "ricotta"]
        let allergens: [String: [String]] = ["Eggs":["egg", "eggs", "mayonnaise"], "Dairy":dairy, "Peanuts":["peanut", "peanuts", "groundnut", "groundnuts"], "Tree nuts":["almond", "almonds", "cashew", "cashews", "walnut", "walnuts", "pecan", "pecans", "pistachio", "pistachios", "hazelnut", "hazelnuts", "macadamia"], "Soy":["soy", "soya", "tofu", "tempeh", "miso", "edamame"], "Sesame":["sesame", "tahini"], "Gluten":["wheat", "flour", "bread", "breadcrumbs", "pasta", "spaghetti", "macaroni", "noodles", "couscous", "semolina", "barley", "rye", "seitan", "bulgur", "malt"]]
        if excludeEggs && (containsEgg(name) || tokens.contains("mayonnaise")) { return true }
        if profile.dairyFree && !tokens.isDisjoint(with: dairy) { return true }
        if profile.allergens.contains(where: { !tokens.isDisjoint(with: allergens[$0] ?? words($0)) }) { return true }
        return terms(profile.avoidIngredients).contains { key($0) == normalized || matches($0, in: name) }
    }
    static func terms(_ text: String) -> [String] { text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty } }
    static func matches(_ term: String, in text: String) -> Bool {
        let source = words(text).joined(separator: " "); let needle = words(term).joined(separator: " ")
        return !needle.isEmpty && (" " + source + " ").contains(" " + needle + " ")
    }
}
struct StockRequirement {
    var ingredient: Ingredient
    var needed: FoodAmount?
}
enum StockEngine {
    static func requirements(_ recipe: Recipe, factor: Double = 1) -> [StockRequirement] {
        var result: [StockRequirement] = []
        for ingredient in recipe.ingredients {
            var amount = FoodAmount.parse(ingredient.amount); if amount != nil { amount!.value *= factor }
            if let amount, let i = result.firstIndex(where: { IngredientRules.key($0.ingredient.name) == IngredientRules.key(ingredient.name) && $0.needed?.dimension == amount.dimension }) {
                result[i].needed!.value += amount.value
                result[i].ingredient.amount = result[i].needed!.text
            } else { result.append(StockRequirement(ingredient: Ingredient(name: ingredient.name, amount: FoodAmount.scaled(ingredient.amount, by: factor)), needed: amount)) }
        }
        return result
    }
    static func available(_ ingredient: String, unit: String, in stock: [Grocery]) -> Double {
        stock.filter { $0.available && IngredientRules.key($0.name) == IngredientRules.key(ingredient) }.compactMap { FoodAmount.parse($0.quantity) }.filter { $0.unit == unit }.reduce(0) { $0 + $1.value }
    }
    static func satisfies(_ requirement: StockRequirement, stock: [Grocery]) -> Bool {
        guard IngredientRules.has(requirement.ingredient.name, in: stock) else { return false }
        guard let amount = requirement.needed else { return requirement.ingredient.amount.rangeOfCharacter(from: .decimalDigits) == nil }
        return available(requirement.ingredient.name, unit: amount.unit, in: stock) + 0.0001 >= amount.value
    }
    static func ready(_ recipe: Recipe, stock: [Grocery], factor: Double = 1) -> Bool {
        !recipe.ingredients.isEmpty && requirements(recipe, factor: factor).allSatisfy { satisfies($0, stock: stock) }
    }
    static func shortfall(_ recipe: Recipe, stock: [Grocery], factor: Double = 1) -> [Ingredient] {
        requirements(recipe, factor: factor).compactMap { r in
            guard !satisfies(r, stock: stock) else { return nil }
            guard var amount = r.needed else { return r.ingredient }
            amount.value = max(0, amount.value - available(r.ingredient.name, unit: amount.unit, in: stock))
            return Ingredient(name: r.ingredient.name, amount: amount.text)
        }
    }
    static func consume(_ recipe: Recipe, stock: inout [Grocery], factor: Double) -> Int {
        var unchanged = 0
        for r in requirements(recipe, factor: factor) {
            guard let amount = r.needed else { unchanged += 1; continue }
            var remaining = amount.value
            let indices = stock.indices.filter { stock[$0].available && IngredientRules.key(stock[$0].name) == IngredientRules.key(r.ingredient.name) }.sorted { (stock[$0].expiry ?? .distantFuture) < (stock[$1].expiry ?? .distantFuture) }
            for i in indices {
                guard var q = FoodAmount.parse(stock[i].quantity), q.unit == amount.unit else { continue }
                let used = min(q.value, remaining); q.value -= used; remaining -= used
                stock[i].quantity = q.text
                if q.value < 0.0001 { stock[i].inStock = false }
                if remaining < 0.0001 { break }
            }
            if remaining > 0.0001 { unchanged += 1 }
        }
        return unchanged
    }
}
enum RecommendationEngine {
    static func allowed(_ recipe: Recipe, data: PantryData) -> Bool {
        recipe.ingredients.allSatisfy { IngredientRules.isVegetarian($0.name) && !IngredientRules.conflicts($0.name, profile: data.profile, excludeEggs: data.excludeEggs) }
    }
    static func score(_ recipe: Recipe, profile: UserProfile, history: [MealEvent], favourites: [String], ratings: [String: Int], details: RecipeDetails?) -> Int {
        let text = recipe.title + " " + recipe.ingredients.map(\.name).joined(separator: " ")
        var result = favourites.contains(recipe.id) ? 30 : 0
        let rating = ratings[recipe.id] ?? 3
        if rating > 0 { result += rating * 4 - 12 }
        result += IngredientRules.terms(profile.preferredIngredients).filter { IngredientRules.matches($0, in: text) }.count * 6
        result -= IngredientRules.terms(profile.dislikes).filter { IngredientRules.matches($0, in: text) }.count * 8
        result += IngredientRules.terms(profile.preferredCuisines).filter { IngredientRules.matches($0, in: recipe.title + " " + (details?.cuisine ?? "")) }.count * 6
        for event in history.suffix(100) {
            if event.recipeID == recipe.id { result += 2 }
            else if IngredientRules.key(event.mainIngredient) == IngredientRules.key(recipe.mainIngredient) { result += 1 }
        }
        return result
    }
    static func rank(_ data: PantryData) -> [Recipe] {
        // Pantry and shopping data deliberately do not participate in recommendation scores.
        data.recipes.filter { allowed($0, data: data) }.sorted {
            let a = score($0, profile: data.profile, history: data.history, favourites: data.favourites, ratings: data.ratings, details: data.recipeDetails[$0.id])
            let b = score($1, profile: data.profile, history: data.history, favourites: data.favourites, ratings: data.ratings, details: data.recipeDetails[$1.id])
            return a == b ? $0.title < $1.title : a > b
        }
    }
}
enum ShoppingEngine {
    static func combine(_ ingredients: [Ingredient]) -> [Ingredient] {
        var result: [Ingredient] = []
        for ingredient in ingredients {
            if let q = FoodAmount.parse(ingredient.amount), let i = result.firstIndex(where: { IngredientRules.key($0.name) == IngredientRules.key(ingredient.name) && FoodAmount.parse($0.amount)?.unit == q.unit }), let old = FoodAmount.parse(result[i].amount) {
                result[i].amount = FoodAmount(value: q.value + old.value, unit: q.unit).text
            } else if !result.contains(ingredient) { result.append(ingredient) }
        }
        return result
    }
}

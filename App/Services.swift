import Foundation

struct LibraryError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
enum OnlineLibrary {
    static func json(_ url: URL) async throws -> [String: Any] {
        let request = URLRequest(url: url, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LibraryError(message: "The library is unavailable or its request limit was reached. Please try again later.")
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibraryError(message: "The library returned an unreadable response.")
        }
        return result
    }
    static func vegetarianIDs() async throws -> [String] {
        let result = try await json(URL(string: "https://www.themealdb.com/api/json/v1/1/filter.php?c=Vegetarian")!)
        guard let meals = result["meals"] as? [[String: Any]] else { throw LibraryError(message: "No vegetarian recipe catalogue was returned.") }
        return meals.compactMap { $0["idMeal"] as? String }
    }
    static func indianVegetarianIDs() async throws -> [String] {
        let terms = ["dal", "paneer", "chana", "aloo", "masala", "biryani", "samosa", "dosa", "bhaji", "saag", "rajma", "curry", "korma"]
        var ids = Set<String>()
        for term in terms {
            var parts = URLComponents(string: "https://www.themealdb.com/api/json/v1/1/search.php")!
            parts.queryItems = [URLQueryItem(name: "s", value: term)]
            let result = try await json(parts.url!)
            for row in result["meals"] as? [[String: Any]] ?? [] {
                if ["India", "Indian"].contains(row["strArea"] as? String ?? ""), ["Vegetarian", "Vegan"].contains(row["strCategory"] as? String ?? ""), let id = row["idMeal"] as? String { ids.insert(id) }
            }
        }
        return ids.sorted()
    }
    static func recipe(id: String) async throws -> Recipe? {
        var components = URLComponents(string: "https://www.themealdb.com/api/json/v1/1/lookup.php")!
        components.queryItems = [URLQueryItem(name: "i", value: id)]
        let result = try await json(components.url!)
        guard let meal = (result["meals"] as? [[String: Any]])?.first,
              ["Vegetarian", "Vegan"].contains(meal["strCategory"] as? String ?? ""),
              let title = meal["strMeal"] as? String,
              let instructions = meal["strInstructions"] as? String else { return nil }
        let ingredients = (1...20).compactMap { index -> Ingredient? in
            guard let name = meal["strIngredient\(index)"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Ingredient(name: name.trimmingCharacters(in: .whitespacesAndNewlines), amount: (meal["strMeasure\(index)"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !ingredients.isEmpty, ingredients.allSatisfy({ IngredientRules.isVegetarian($0.name) }) else { return nil }
        return Recipe(id: id, title: title, ingredients: ingredients, instructions: instructions, source: "https://www.themealdb.com/meal/\(id)", image: meal["strMealThumb"] as? String)
    }
    static func nutrition(query: String) async throws -> [Nutrition] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [URLQueryItem(name: "api_key", value: "DEMO_KEY"), URLQueryItem(name: "query", value: query), URLQueryItem(name: "pageSize", value: "10"), URLQueryItem(name: "dataType", value: "Foundation,SR Legacy")]
        let result = try await json(components.url!)
        guard let foods = result["foods"] as? [[String: Any]] else { return [] }
        return foods.compactMap { food in
            guard let id = food["fdcId"] as? Int, let description = food["description"] as? String else { return nil }
            let nutrients = food["foodNutrients"] as? [[String: Any]] ?? []
            func value(_ id: Int) -> Double? { nutrients.first { ($0["nutrientId"] as? Int) == id }?["value"] as? Double }
            return Nutrition(sourceID: id, description: description, calories: value(1008), protein: value(1003), carbs: value(1005), fat: value(1004))
        }
    }
}

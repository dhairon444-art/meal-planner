import Foundation
@main struct RuleChecks {
    @MainActor static func main() throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        check(IngredientRules.key("tomatoes") == IngredientRules.key("tomato"), "Plural alias")
        check(IngredientRules.key("yogurt") == IngredientRules.key("yoghurt"), "Regional alias")
        check(IngredientRules.key("red lentils") != IngredientRules.key("lentils"), "Preserve types")
        check(IngredientRules.containsEgg("egg noodles") && !IngredientRules.containsEgg("eggplant"), "Eggplant is egg-free")
        for name in ["chicken stock", "fish sauce", "gelatine", "bacon", "prawns", "duck", "beef mince"] { check(!IngredientRules.isVegetarian(name), "Reject \(name)") }
        check(FoodAmount.parse("1/2 kg") == FoodAmount(value: 500, unit: "g"), "Fraction conversion")
        check(FoodAmount.parse("1 1/2 kg") == FoodAmount(value: 1500, unit: "g"), "Mixed fraction")
        check(FoodAmount.parse("½ kg") == FoodAmount(value: 500, unit: "g"), "Unicode fraction")
        check(FoodAmount.parse(FoodAmount(value: 1500, unit: "g").text) == FoodAmount(value: 1500, unit: "g"), "Generated large amounts can be parsed again")
        check(FoodAmount.parse(FoodAmount(value: 0.001, unit: "g").text) == FoodAmount(value: 0.001, unit: "g"), "Small amounts preserve precision")
        check(FoodAmount.parse("200 gms") == FoodAmount(value: 200, unit: "g"), "Imported grams normalize")
        check(FoodAmount.parse("2 teaspoons") == FoodAmount(value: 10, unit: "ml"), "Imported teaspoon units normalize")
        check(FoodAmount.parse("2 cloves") == FoodAmount(value: 2, unit: "clove"), "Count units")
        check(FoodAmount.parse("400g tin") == nil, "Do not invent package conversions")
        let recipe = Recipe(id: "a", title: "Tomato rice", ingredients: [Ingredient(name: "tomato", amount: "500 g"), Ingredient(name: "rice", amount: "100 g")], instructions: "Cook.", source: "https://example.com", image: nil)
        let other = Recipe(id: "b", title: "Lentil bowl", ingredients: [Ingredient(name: "lentil", amount: "200 g")], instructions: "Cook.", source: "https://example.com", image: nil)
        let stock = [Grocery(name: "tomatoes", quantity: "0.5 kg", category: "Produce"),Grocery(name: "rice", quantity: "100 g", category: "Grains")]
        check(StockEngine.ready(recipe, stock: stock), "Equivalent units make recipe ready")
        check(!StockEngine.ready(recipe, stock: Array(stock.prefix(1))), "Missing ingredient blocks readiness")
        var insufficient = stock; insufficient[0].quantity = "100 g"
        check(!StockEngine.ready(recipe, stock: insufficient), "Insufficient quantity blocks readiness")
        check(StockEngine.shortfall(recipe, stock: insufficient).first?.amount == "400 g", "Only deficit is needed")
        var expired = stock; expired[0].expiry = Calendar.current.date(byAdding: .day, value: -1, to: .now)
        check(!StockEngine.ready(recipe, stock: expired), "Expired stock does not count")
        var absent = stock; absent[0].inStock = false
        check(!StockEngine.ready(recipe, stock: absent), "Not-in-stock items do not count")
        var unknown = stock; unknown[0].quantity = ""
        check(!StockEngine.ready(recipe, stock: unknown), "Unknown stock amount blocks measured requirement")
        let repeated = Recipe(id: "c", title: "Double tomato", ingredients: [Ingredient(name: "tomato", amount: "400 g"), Ingredient(name: "tomatoes", amount: "400 g")], instructions: "Cook.", source: "", image: nil)
        check(!StockEngine.ready(repeated, stock: stock), "Duplicate recipe ingredients aggregate before checking")
        var data = PantryData(groceries: stock, recipes: [recipe, other]); data.profile.preferredIngredients = "lentil"
        let order = RecommendationEngine.rank(data).map(\.id)
        data.groceries = []
        check(order == RecommendationEngine.rank(data).map(\.id), "Recommendations independent of stock")
        data.shopping = [ShoppingItem(name: "tomato", quantity: "1 kg"),ShoppingItem(name: "rice", quantity: "1 kg")]
        check(!StockEngine.ready(recipe, stock: data.groceries), "Shopping never becomes stock")
        data.profile.avoidIngredients = "rice"
        check(!RecommendationEngine.rank(data).contains(where: { $0.id == recipe.id }), "Hard exclusions filter out recipes")
        var profile = UserProfile(); profile.allergens = ["Dairy"]
        check(IngredientRules.conflicts("paneer", profile: profile, excludeEggs: false), "Allergy aliases")
        profile.allergens = ["Peanuts"]
        check(IngredientRules.conflicts("peanut butter", profile: profile, excludeEggs: false), "Compound allergen ingredient")
        let combined = ShoppingEngine.combine([Ingredient(name: "tomato", amount: "0.5 kg"),Ingredient(name: "tomatoes", amount: "300 g"),Ingredient(name: "tomato", amount: "1 tin")])
        check(combined.count == 2 && combined.first?.amount == "800 g", "Consolidate compatible quantities and keep packages distinct")
        var consumed = stock; _ = StockEngine.consume(recipe, stock: &consumed, factor: 1)
        check(consumed.allSatisfy { $0.inStock == false }, "Cooking deducts measured stock")
        let old = #"{"groceries":[],"shopping":[],"recipes":[],"excludeEggs":true}"#.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(PantryData.self, from: old)
        check(migrated.excludeEggs && migrated.history.isEmpty && migrated.profile.householdSize == 1, "Migrate existing app data")
        data = PantryData(groceries: stock, recipes: [recipe, other]); data.profile.householdSize = 2
        let store = PantryStore(initialData: data)
        store.data.recipeDetails[recipe.id] = RecipeDetails(baseServings: 2, minutes: 20, estimatedCost: 4)
        store.data.recipeDetails[other.id] = RecipeDetails(baseServings: 2, minutes: 15, estimatedCost: 3)
        store.data.planningMealCount = 7
        store.generatePlan()
        check(store.data.plans.count == 7 && !store.data.planApproved, "Weekly draft created for review")
        let day = store.data.planningStart
        store.plan(recipe, date: day, slot: "Dinner", servings: 4)
        check(store.data.plans.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.slot == "Dinner" }.count == 1, "Replace same slot instead of duplicating")
        store.data.plans = [PlannedMeal(date: day, slot: "Dinner", recipeID: recipe.id, servings: 2), PlannedMeal(date: day, slot: "Lunch", recipeID: recipe.id, servings: 2)]
        let deficit = store.planShopping()
        check(deficit.first(where: { $0.name == "tomato" })?.amount == "500 g", "Weekly planning subtracts stock once after aggregating")
        store.buy(deficit); store.buy(deficit)
        check(store.data.shopping.first(where: { $0.name == "tomato" })?.quantity == "500 g", "Repeated plan shopping is idempotent")
        store.data.shopping = [ShoppingItem(name: "lentil", quantity: "200 g", purchased: true)]
        store.movePurchased()
        check(store.data.shopping.isEmpty && store.data.groceries.contains(where: { $0.name == "lentil" && $0.available }), "Purchase movement confirms stock")
        let planID = store.data.plans[0].id
        store.markCooked(recipe, servings: 2, deduct: true, planID: planID)
        store.markCooked(recipe, servings: 2, deduct: true, planID: planID)
        check(store.data.history.count == 1, "Completed planned meals cannot be double logged")
        let restored = try JSONDecoder().decode(PantryData.self, from: JSONEncoder().encode(store.data))
        check(restored.history == store.data.history && restored.plans == store.data.plans && restored.profile == store.data.profile, "Expanded data round trip")
        let second = Recipe(id: "d", title: "Tomato bowl", ingredients: [Ingredient(name: "tomatoes", amount: "300 g")], instructions: "Cook.", source: "", image: nil)
        let auto = PantryStore(initialData: PantryData(groceries: [Grocery(name: "tomato", quantity: "200 g", category: "Produce")], shopping: [ShoppingItem(name: "bread", quantity: "1")], recipes: [recipe, second]))
        auto.selectRecipe(recipe)
        check(auto.data.shopping.first(where: { $0.name == "tomato" })?.quantity == "300 g", "Selecting a recipe adds only its pantry deficit")
        auto.selectRecipe(second)
        check(auto.data.shopping.first(where: { $0.name == "tomato" })?.quantity == "600 g", "Multiple selections aggregate before subtracting pantry")
        auto.data.groceries[0].quantity = "500 g"; auto.save()
        check(auto.data.shopping.first(where: { $0.name == "tomato" })?.quantity == "300 g", "Shopping updates as pantry stock changes")
        check(auto.data.shopping.contains(where: { $0.name == "bread" }), "Manual shopping survives recalculation")
        auto.removeSelectedRecipe(second)
        check(!auto.data.shopping.contains(where: { $0.name == "tomato" }), "Removing a selection removes its excess requirement")
        check(auto.data.shopping.contains(where: { $0.name == "bread" }), "Removing selected recipe preserves manual shopping")
        let breakfast = Recipe(id: "breakfast", title: "Kanda Poha", ingredients: [Ingredient(name: "poha", amount: "1 cup")], instructions: "Cook.", source: "", image: nil)
        let snack = Recipe(id: "snack", title: "Suji Poha Bites", ingredients: [Ingredient(name: "poha", amount: "1 cup")], instructions: "Cook.", source: "", image: nil)
        check(MealTypeEngine.types(breakfast, details: nil).contains("Breakfast"), "Breakfast suggestion")
        check(MealTypeEngine.types(snack, details: nil).contains("Snacks"), "Snack suggestion")
        var customDetails = RecipeDetails(); customDetails.mealTypes = ["Dinner"]
        check(MealTypeEngine.types(breakfast, details: customDetails) == ["Dinner"], "User override takes priority")
        customDetails.mealTypes = []
        check(MealTypeEngine.types(breakfast, details: customDetails).isEmpty, "User may clear categories")
        let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Resources/SeedRecipes.json")
        let recipes = try JSONDecoder().decode([Recipe].self, from: Data(contentsOf: url))
        check(recipes.count >= 109 && Set(recipes.map(\.id)).count == recipes.count, "Recipe catalogue integrity")
        check(recipes.filter { $0.id.hasPrefix("personal-") }.count == 17, "All 17 personal recipes imported")
        check(recipes.allSatisfy { !$0.instructions.isEmpty && $0.ingredients.allSatisfy { IngredientRules.isVegetarian($0.name) } }, "Vegetarian library")
        print("Passed \(count) checks: migration, preference-based recommendations, restrictions, units, readiness, stock consumption, meal plans, consolidated shopping, purchases, history and catalogue integrity.")
    }
}

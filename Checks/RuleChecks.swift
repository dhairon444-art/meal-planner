import Foundation
@main struct RuleChecks {
    static func main() throws {
        func check(_ value: Bool, _ message: String) { precondition(value, message) }
        check(IngredientRules.key("tomatoes") == IngredientRules.key("tomato"), "Plural alias")
        check(IngredientRules.key("yogurt") == IngredientRules.key("yoghurt"), "Regional alias")
        check(IngredientRules.key("red lentils") != IngredientRules.key("lentils"), "Keep ingredient types distinct")
        check(IngredientRules.containsEgg("egg noodles"), "Egg-containing ingredient")
        check(!IngredientRules.containsEgg("eggplant"), "Eggplant is egg-free")
        for name in ["chicken stock", "fish sauce", "gelatine", "bacon", "prawns", "duck", "beef mince"] { check(!IngredientRules.isVegetarian(name), "Reject \(name)") }
        for name in ["chickpeas", "eggplant", "tofu", "vegetable stock", "rice"] { check(IngredientRules.isVegetarian(name), "Accept \(name)") }
        let pantry = [Grocery(name: "tomatoes", quantity: "500 g", category: "Produce")]
        let recipe = Recipe(id: "test", title: "Test", ingredients: [Ingredient(name: "tomato", amount: "200 g"),Ingredient(name: "rice", amount: "100 g")], instructions: "", source: "", image: nil)
        check(IngredientRules.missing(recipe, in: pantry).map(\.name) == ["rice"], "Missing ingredient calculation")
        let url = URL(fileURLWithPath: "outputs/GreenPantry/App/Resources/SeedRecipes.json")
        let recipes = try JSONDecoder().decode([Recipe].self, from: Data(contentsOf: url))
        check(recipes.count == 86, "Recipe library is complete")
        check(Set(recipes.map(\.id)).count == recipes.count, "Unique recipe IDs")
        check(recipes.allSatisfy { !$0.instructions.isEmpty && !$0.ingredients.isEmpty && $0.ingredients.allSatisfy { IngredientRules.isVegetarian($0.name) } }, "Vegetarian library integrity")
        let original = PantryData(groceries: pantry, recipes: recipes)
        let restored = try JSONDecoder().decode(PantryData.self, from: JSONEncoder().encode(original))
        check(restored.groceries == pantry && restored.recipes == recipes, "Persistence round trip")
        print("Passed ingredient aliases, vegetarian filtering, egg exclusions, recipe matching, 86-recipe library validation, and persistence checks.")
    }
}

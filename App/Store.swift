import Foundation
import Observation
import WidgetKit

@MainActor @Observable final class PantryStore {
    var data: PantryData
    var notice: String?
    var importing = false
    var importStatus = ""
    var readOnly = false
    private var persists = true
    init(initialData: PantryData? = nil) {
        if let initialData { data = initialData; persists = false; return }
        do { data = try PantryDisk.read() }
        catch { data = PantryData(); readOnly = true; notice = "Your saved data could not be read. It has been preserved. Restore a backup from Settings to recover it." }
        if !readOnly { try? PantryDisk.updateWidget(data) }
    }
    var recipes: [Recipe] { RecommendationEngine.rank(data) }
    func refresh() {
        guard !readOnly else { return }
        do { data = try PantryDisk.read() } catch { notice = "Could not refresh saved data. Your current session has been kept." }
    }
    func save() {
        guard persists else { return }
        guard !readOnly else { notice = "Restore a valid backup before saving changes. Your existing file has been preserved."; return }
        do { try PantryDisk.write(data) }
        catch { notice = "Your changes could not be saved: \(error.localizedDescription)"; return }
        do { try PantryDisk.updateWidget(data); WidgetCenter.shared.reloadAllTimelines() }
        catch { notice = "Your changes are saved. The widget could not refresh yet." }
    }
    func permitted(_ name: String) -> Bool { IngredientRules.isVegetarian(name) && !IngredientRules.conflicts(name, profile: data.profile, excludeEggs: data.excludeEggs) }
    func add(_ groceries: [Grocery]) { data.groceries.append(contentsOf: groceries); save() }
    func details(_ recipe: Recipe) -> RecipeDetails { data.recipeDetails[recipe.id] ?? RecipeDetails() }
    func factor(_ recipe: Recipe, servings: Int?) -> Double {
        guard let servings, let base = details(recipe).baseServings, base > 0 else { return 1 }
        return Double(servings) / Double(base)
    }
    func toggleFavourite(_ recipe: Recipe) {
        if data.favourites.contains(recipe.id) { data.favourites.removeAll { $0 == recipe.id } } else { data.favourites.append(recipe.id) }
        save()
    }
    func buy(_ ingredients: [Ingredient]) {
        for item in ShoppingEngine.combine(ingredients) where permitted(item.name) {
            if let q = FoodAmount.parse(item.amount), let i = data.shopping.firstIndex(where: { !$0.purchased && IngredientRules.key($0.name) == IngredientRules.key(item.name) && FoodAmount.parse($0.quantity)?.unit == q.unit }), let existing = FoodAmount.parse(data.shopping[i].quantity) {
                data.shopping[i].quantity = FoodAmount(value: max(existing.value, q.value), unit: q.unit).text
            } else if !data.shopping.contains(where: { !$0.purchased && IngredientRules.key($0.name) == IngredientRules.key(item.name) && $0.quantity == item.amount }) {
                data.shopping.append(ShoppingItem(name: item.name, quantity: item.amount))
            }
        }
        save()
    }
    func movePurchased() {
        let items = data.shopping.filter { $0.purchased && permitted($0.name) }
        data.groceries.append(contentsOf: items.map { Grocery(name: $0.name, quantity: $0.quantity, category: "Other", inStock: true) })
        let ids = Set(items.map(\.id)); data.shopping.removeAll { ids.contains($0.id) }; save()
    }
    func plan(_ recipe: Recipe, date: Date, slot: String, servings: Int) {
        guard RecommendationEngine.allowed(recipe, data: data) else { notice = "This recipe conflicts with your current restrictions."; return }
        if let i = data.plans.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.slot == slot }) {
            data.plans[i] = PlannedMeal(date: date, slot: slot, recipeID: recipe.id, servings: servings)
        } else { data.plans.append(PlannedMeal(date: date, slot: slot, recipeID: recipe.id, servings: servings)) }
        data.planApproved = false; save()
    }
    func generatePlan() {
        let suitable = recipes.filter { recipe in
            let info = details(recipe)
            if let max = data.profile.maxCookingMinutes { guard let minutes = info.minutes, minutes <= max else { return false } }
            let required = IngredientRules.terms(info.equipment)
            let owned = IngredientRules.terms(data.profile.equipment)
            if !owned.isEmpty && required.contains(where: { !owned.contains($0) }) { return false }
            return true
        }
        if suitable.isEmpty { notice = "No recipes meet your planning constraints. Add recipe cooking times or adjust the time/equipment preferences."; return }
        let start = Calendar.current.startOfDay(for: data.planningStart)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        data.plans.removeAll { $0.date >= start && $0.date < end && !$0.completed }
        for index in 0..<min(data.planningMealCount, 21) {
            let date = Calendar.current.date(byAdding: .day, value: index / 3, to: start)!
            // For <=7 meals, draft one dinner per day. Larger plans fill three slots each day.
            let day = data.planningMealCount <= 7 ? Calendar.current.date(byAdding: .day, value: index, to: start)! : date
            let slot = data.planningMealCount <= 7 ? "Dinner" : ["Breakfast", "Lunch", "Dinner"][index % 3]
            if !data.plans.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.slot == slot && $0.completed }) {
                data.plans.append(PlannedMeal(date: day, slot: slot, recipeID: suitable[index % suitable.count].id, servings: data.profile.householdSize))
            }
        }
        data.planApproved = false; save()
    }
    func unscaledPlanRecipes() -> [Recipe] {
        let start = Calendar.current.startOfDay(for: data.planningStart)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let ids = Set(data.plans.filter { !$0.completed && $0.date >= start && $0.date < end }.map(\.recipeID))
        return data.recipes.filter { ids.contains($0.id) && details($0).baseServings == nil }
    }
    func planShopping() -> [Ingredient] {
        let start = Calendar.current.startOfDay(for: data.planningStart)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let meals = data.plans.filter { !$0.completed && $0.date >= start && $0.date < end }
        let raw = meals.flatMap { meal -> [Ingredient] in
            guard let recipe = data.recipes.first(where: { $0.id == meal.recipeID }), RecommendationEngine.allowed(recipe, data: data) else { return [] }
            return StockEngine.requirements(recipe, factor: factor(recipe, servings: meal.servings)).map(\.ingredient)
        }
        return ShoppingEngine.combine(raw).compactMap { ingredient in
            guard var q = FoodAmount.parse(ingredient.amount) else { return IngredientRules.has(ingredient.name, in: data.groceries) ? nil : ingredient }
            q.value -= StockEngine.available(ingredient.name, unit: q.unit, in: data.groceries)
            return q.value > 0.0001 ? Ingredient(name: ingredient.name, amount: q.text) : nil
        }
    }
    func markCooked(_ recipe: Recipe, servings: Int, deduct: Bool, planID: UUID? = nil) {
        guard RecommendationEngine.allowed(recipe, data: data) else { notice = "This recipe conflicts with your current dietary restrictions."; return }
        if let planID, data.plans.first(where: { $0.id == planID })?.completed == true { return }
        var unchanged = 0
        let unknownServings = deduct && details(recipe).baseServings == nil
        if deduct && !unknownServings { unchanged = StockEngine.consume(recipe, stock: &data.groceries, factor: factor(recipe, servings: servings)) }
        data.history.append(MealEvent(date: .now, recipeID: recipe.id, title: recipe.title, mainIngredient: recipe.mainIngredient, servings: servings))
        if let planID, let i = data.plans.firstIndex(where: { $0.id == planID }) { data.plans[i].completed = true }
        save()
        notice = unknownServings ? "Meal saved. Set original recipe servings before deducting stock; pantry amounts were kept unchanged." : unchanged > 0 ? "Meal saved to history. \(unchanged) ingredient amounts need checking in your pantry." : "Meal saved to your cooking history."
    }
    func importRecipes(indian: Bool = false) async {
        guard !importing else { return }; importing = true; defer { importing = false }
        do {
            let ids = try await (indian ? OnlineLibrary.indianVegetarianIDs() : OnlineLibrary.vegetarianIDs()); let existing = Set(data.recipes.map(\.id)); let pending = ids.filter { !existing.contains($0) }
            var count = 0
            for (index, id) in pending.enumerated() {
                try Task.checkCancellation(); importStatus = "Loading recipe \(index + 1) of \(pending.count)"
                if let recipe = try await OnlineLibrary.recipe(id: id) { data.recipes.append(recipe); count += 1; save() }
            }
            notice = "Added \(count) vegetarian recipes. \(data.recipes.count) saved for offline use."
        } catch { notice = "Import stopped. Downloaded recipes are saved. \(error.localizedDescription)" }
    }
}

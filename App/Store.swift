import Foundation
import Observation
import WidgetKit

@MainActor @Observable final class PantryStore {
    var data = PantryDisk.read()
    var notice: String?
    var importing = false
    var importStatus = ""
    init() { save() }
    var recipes: [Recipe] {
        data.recipes.filter { !data.excludeEggs || !$0.containsEgg }.sorted {
            let a = IngredientRules.missing($0, in: data.groceries).count
            let b = IngredientRules.missing($1, in: data.groceries).count
            return a == b ? $0.title < $1.title : a < b
        }
    }
    func save() {
        do { try PantryDisk.write(data); WidgetCenter.shared.reloadAllTimelines() }
        catch { notice = "Your changes could not be saved: \(error.localizedDescription)" }
    }
    func add(_ groceries: [Grocery]) { data.groceries.append(contentsOf: groceries); save() }
    func buy(_ ingredients: [Ingredient]) {
        for item in ingredients where !data.shopping.contains(where: { !$0.purchased && IngredientRules.key($0.name) == IngredientRules.key(item.name) }) {
            data.shopping.append(ShoppingItem(name: item.name, quantity: item.amount))
        }
        save()
    }
    func importRecipes() async {
        guard !importing else { return }
        importing = true
        defer { importing = false }
        do {
            let ids = try await OnlineLibrary.vegetarianIDs()
            let existing = Set(data.recipes.map(\.id))
            let pending = ids.filter { !existing.contains($0) }
            var count = 0
            for (index, id) in pending.enumerated() {
                try Task.checkCancellation()
                importStatus = "Loading recipe \(index + 1) of \(pending.count)"
                if let recipe = try await OnlineLibrary.recipe(id: id) { data.recipes.append(recipe); count += 1; save() }
            }
            notice = "Added \(count) vegetarian recipes. \(data.recipes.count) saved for offline use."
        } catch { notice = "Import stopped. Recipes already downloaded are saved. \(error.localizedDescription)" }
    }
}

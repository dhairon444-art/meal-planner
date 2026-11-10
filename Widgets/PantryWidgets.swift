import SwiftUI
import WidgetKit

struct PantryEntry: TimelineEntry {
    var date: Date
    var data: PantryData
}
struct PantryProvider: TimelineProvider {
    func placeholder(in context: Context) -> PantryEntry { PantryEntry(date: .now, data: PantryData()) }
    func getSnapshot(in context: Context, completion: @escaping (PantryEntry) -> Void) { completion(PantryEntry(date: .now, data: WidgetSnapshot.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PantryEntry>) -> Void) {
        completion(Timeline(entries: [PantryEntry(date: .now, data: WidgetSnapshot.read())], policy: .after(.now.addingTimeInterval(1800))))
    }
}
struct PantryWidgetView: View {
    let entry: PantryEntry
    let recipeMode: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(recipeMode ? "Cook from your pantry" : "Shopping list", systemImage: recipeMode ? "leaf.fill" : "basket.fill")
                .font(.headline).foregroundStyle(.green)
            if recipeMode {
                let recipes = entry.data.recipes.filter { !entry.data.excludeEggs || !$0.containsEgg }
                if let recipe = recipes.min(by: { IngredientRules.missing($0, in: entry.data.groceries).count < IngredientRules.missing($1, in: entry.data.groceries).count }) {
                    Text(recipe.title).font(.headline)
                    Text("\(IngredientRules.missing(recipe, in: entry.data.groceries).count) ingredients missing · check quantities").font(.caption).foregroundStyle(.secondary)
                } else { Text("Download vegetarian recipes in the app.").font(.caption) }
            } else {
                let items = entry.data.shopping.filter { !$0.purchased }
                if items.isEmpty { Text("Your list is clear.").foregroundStyle(.secondary) }
                ForEach(items.prefix(4)) { item in
                    HStack { Image(systemName: "circle"); Text(item.name).lineLimit(1); Spacer(); Text(item.quantity).font(.caption) }
                }
                if items.count > 4 { Text("+\(items.count - 4) more").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: recipeMode ? "greenpantry://recipes" : "greenpantry://shopping"))
        .containerBackground(.green.opacity(0.07), for: .widget)
    }
}
@main struct PantryWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShoppingWidget()
        RecipeWidget()
    }
}
struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GreenPantryShopping", provider: PantryProvider()) { PantryWidgetView(entry: $0, recipeMode: false) }
            .configurationDisplayName("Shopping list").description("Your next grocery trip at a glance.").supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct RecipeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GreenPantryRecipe", provider: PantryProvider()) { PantryWidgetView(entry: $0, recipeMode: true) }
            .configurationDisplayName("Cook from your pantry").description("A vegetarian recipe matched to your ingredients.").supportedFamilies([.systemSmall, .systemMedium])
    }
}

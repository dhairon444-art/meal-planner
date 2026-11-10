import SwiftUI

struct RecipesView: View {
    @Environment(PantryStore.self) private var store
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Make more of what you have", systemImage: "sparkles").font(.headline).foregroundStyle(.green)
                    Text("Recipes are ranked by missing ingredient names. Check quantities and dietary labels before cooking.").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await store.importRecipes() } } label: {
                        if store.importing { ProgressView(store.importStatus) } else { Label("Download vegetarian recipes", systemImage: "arrow.down.circle") }
                    }.disabled(store.importing)
                }
                if store.recipes.isEmpty {
                    ContentUnavailableView("Build your recipe library", systemImage: "book", description: Text("Download vegetarian recipes from TheMealDB. Your pantry stays on your phone."))
                }
                ForEach(store.recipes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { recipe in
                    NavigationLink { RecipeDetail(recipe: recipe) } label: {
                        HStack(spacing: 14) {
                            AsyncImage(url: recipe.image.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.green.opacity(0.12)).overlay(Image(systemName: "leaf")) }
                                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(recipe.title).font(.headline)
                                let missing = IngredientRules.missing(recipe, in: store.data.groceries)
                                Text(missing.isEmpty ? "All ingredient names matched · check quantities" : "\(missing.count) of \(recipe.ingredients.count) ingredients missing")
                                    .font(.caption).foregroundStyle(missing.isEmpty ? .green : .secondary)
                            }
                        }.padding(.vertical, 3)
                    }
                }
                Section { Link("Recipes provided by TheMealDB", destination: URL(string: "https://www.themealdb.com")!).font(.caption) }
            }
            .navigationTitle("What’s cooking?").searchable(text: $search, prompt: "Find a vegetarian recipe")
        }
    }
}
struct RecipeDetail: View {
    @Environment(PantryStore.self) private var store
    let recipe: Recipe
    @State private var ideas: [SubstituteIdea] = []
    @State private var busy = false
    @State private var error: String?
    var missing: [Ingredient] { IngredientRules.missing(recipe, in: store.data.groceries) }
    var body: some View {
        List {
            Section {
                AsyncImage(url: recipe.image.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Color.green.opacity(0.12) }
                    .frame(height: 210).clipped().listRowInsets(EdgeInsets())
                Text(recipe.title).font(.title2.bold())
                Text("Vegetarian source category. Check cheese for vegetarian rennet, packaged sauces, allergens and quantities.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Ingredients") {
                ForEach(recipe.ingredients) { ingredient in
                    HStack {
                        Image(systemName: IngredientRules.has(ingredient.name, in: store.data.groceries) ? "checkmark.circle.fill" : "circle").foregroundStyle(.green)
                        Text(ingredient.name.capitalized)
                        Spacer()
                        Text(ingredient.amount).foregroundStyle(.secondary)
                    }
                }
                if !missing.isEmpty {
                    Button("Add \(missing.count) missing ingredients to shopping") { store.buy(missing); store.notice = "Missing ingredients added to your shopping list." }
                    Button { Task { await suggest() } } label: {
                        if busy { ProgressView("Checking your pantry…") } else { Label("Find substitutes in my pantry", systemImage: "sparkles") }
                    }.disabled(busy || !PantryIntelligence.available)
                }
                Text("Matches compare ingredient names, not available quantities. Review amounts before shopping or cooking.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.secondary) } }
            if !ideas.isEmpty {
                Section("Suggested substitutions · review before use") {
                    ForEach(ideas.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(ideas[i].missingIngredient) → \(ideas[i].availableReplacement)").font(.headline)
                            Text(ideas[i].explanation).font(.subheadline)
                        }
                    }
                }
            }
            Section("Method") { Text(recipe.instructions).textSelection(.enabled) }
            Section { Link("View original on TheMealDB", destination: URL(string: recipe.source)!) }
        }.navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
    }
    private func suggest() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            ideas = try await PantryIntelligence.substitutes(recipe: recipe, groceries: store.data.groceries, excludeEggs: store.data.excludeEggs)
            if ideas.isEmpty { error = "No suitable pantry substitutions were found. You can add the missing ingredients to shopping." }
        } catch { self.error = "Could not suggest substitutes: \(error.localizedDescription)" }
    }
}

struct ShoppingView: View {
    @Environment(PantryStore.self) private var store
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add an item", text: $name)
                        Button("Add", systemImage: "plus.circle.fill") {
                            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard IngredientRules.isVegetarian(value), (!store.data.excludeEggs || !IngredientRules.containsEgg(value)) else { store.notice = "Please add vegetarian ingredients consistent with your settings."; return }
                            store.buy([Ingredient(name: value, amount: "")]); name = ""
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if store.data.shopping.isEmpty {
                    ContentUnavailableView("Nothing to buy yet", systemImage: "basket", description: Text("Missing recipe ingredients will appear here when you add them."))
                }
                ForEach(store.data.shopping) { item in
                    Button {
                        if let index = store.data.shopping.firstIndex(where: { $0.id == item.id }) {
                            store.data.shopping[index].purchased.toggle(); store.save()
                        }
                    } label: {
                        HStack {
                            Image(systemName: item.purchased ? "checkmark.circle.fill" : "circle").foregroundStyle(.green)
                            Text(item.name.capitalized).strikethrough(item.purchased).foregroundStyle(.primary)
                            Spacer()
                            Text(item.quantity).font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("Delete", role: .destructive) { store.data.shopping.removeAll { $0.id == item.id }; store.save() } }
                }
                if store.data.shopping.contains(where: \.purchased) {
                    Section {
                        Button("Move purchased items to pantry") {
                            let bought = store.data.shopping.filter(\.purchased)
                            store.data.groceries.append(contentsOf: bought.map { Grocery(name: $0.name, quantity: $0.quantity, category: "Other") })
                            store.data.shopping.removeAll(where: \.purchased); store.save()
                        }
                    }
                }
            }.navigationTitle("Shopping list")
        }
    }
}

struct SettingsView: View {
    @Environment(PantryStore.self) private var store
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("App", value: "Meal Planner")
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                }
                Section("Diet") {
                    Label("Vegetarian", systemImage: "leaf.fill").foregroundStyle(.green)
                    Toggle("Exclude eggs", isOn: $store.data.excludeEggs).onChange(of: store.data.excludeEggs) { _, _ in store.save() }
                    Text("Dairy is included. Excluding eggs filters recipes and new entries; review existing pantry and shopping items separately.").font(.caption).foregroundStyle(.secondary)
                }
                Section("On-device intelligence") { Text(PantryIntelligence.status) }
                Section("Widgets") {
                    Text("Touch and hold your Home Screen, choose Edit → Add Widget, then find Meal Planner. Choose your shopping list or a recipe suggestion.")
                }
                Section("Privacy & data") {
                    Text("Your pantry stays on this device. Recipe downloads contact TheMealDB. Nutrition searches send the ingredient name to USDA FoodData Central. Substitution suggestions use Apple’s on-device model.")
                    ShareLink("Export pantry backup", item: backup)
                    Text("Keep a backup before removing or reinstalling the app.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Libraries") {
                    Link("TheMealDB · recipe source", destination: URL(string: "https://www.themealdb.com/api.php")!)
                    Link("USDA FoodData Central · nutrition source", destination: URL(string: "https://fdc.nal.usda.gov")!)
                    Text("This development build uses TheMealDB’s test access and USDA’s limited demo access. Nutrition values are per 100 g and require you to confirm the food match.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
        }
    }
    var backup: String { String(data: (try? JSONEncoder().encode(store.data)) ?? Data(), encoding: .utf8) ?? "" }
}

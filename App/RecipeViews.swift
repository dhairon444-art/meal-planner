import SwiftUI

struct RecipesView: View {
    @Environment(PantryStore.self) private var store
    @State private var search = ""
    @State private var favouritesOnly = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Meals for you", systemImage: "sparkles").font(.title2.bold()).foregroundStyle(.green)
                    Text(store.data.history.isEmpty && store.data.profile.preferredIngredients.isEmpty ? "Add your tastes in Profile, save favourites, and log meals to shape your recommendations." : "Suggestions follow your tastes, favourites, and cooking history.").font(.subheadline).foregroundStyle(.secondary)
                    Toggle("Favourites only", isOn: $favouritesOnly)
                }
                ForEach(store.recipes.filter { (!favouritesOnly || store.data.favourites.contains($0.id)) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.ingredients.contains { $0.name.localizedCaseInsensitiveContains(search) }) }) { recipe in
                    NavigationLink { RecipeDetail(recipe: recipe) } label: { RecipeCard(recipe: recipe) }
                }
                if store.recipes.isEmpty {
                    ContentUnavailableView("No matching recipes", systemImage: "leaf", description: Text("Review your dietary restrictions or download more vegetarian recipes."))
                }
                Section {
                    Button { Task { await store.importRecipes() } } label: {
                        if store.importing { ProgressView(store.importStatus) } else { Label("Update recipe library", systemImage: "arrow.down.circle") }
                    }.disabled(store.importing)
                    Link("Recipes provided by TheMealDB", destination: URL(string: "https://www.themealdb.com")!).font(.caption)
                }
            }.navigationTitle("Recipes").searchable(text: $search, prompt: "Find a meal or ingredient")
            .toolbar { NavigationLink { ProfileView() } label: { Image(systemName: "person.crop.circle") } }
        }
    }
}
struct RecipeCard: View {
    @Environment(PantryStore.self) private var store
    let recipe: Recipe
    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: recipe.image.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.green.opacity(0.12)).overlay(Image(systemName: "leaf")) }
                .frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.title).font(.headline)
                Text("Main ingredient: \(recipe.mainIngredient)").font(.caption).foregroundStyle(.secondary)
                if StockEngine.ready(recipe, stock: store.data.groceries) {
                    Label("Ready to cook", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green)
                }
            }
            if store.data.favourites.contains(recipe.id) { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
        }.padding(.vertical, 4)
    }
}
struct RecipeDetail: View {
    @Environment(PantryStore.self) private var store
    let recipe: Recipe
    @State private var ideas: [SubstituteIdea] = []
    @State private var busy = false
    @State private var error: String?
    @State private var servings = 1
    @State private var planning = false
    @State private var editing = false
    @State private var confirmCooking = false
    @State private var deduct = true
    var factor: Double { store.factor(recipe, servings: servings) }
    var missing: [Ingredient] { StockEngine.shortfall(recipe, stock: store.data.groceries, factor: factor) }
    var body: some View {
        List {
            Section {
                AsyncImage(url: recipe.image.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Color.green.opacity(0.12) }.frame(height: 210).clipped().listRowInsets(EdgeInsets())
                Text(recipe.title).font(.title2.bold())
                Text("Main ingredient: \(recipe.mainIngredient)").foregroundStyle(.secondary)
                if StockEngine.ready(recipe, stock: store.data.groceries, factor: factor) { Label("Ready to cook", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                Button { store.toggleFavourite(recipe) } label: { Label(store.data.favourites.contains(recipe.id) ? "Saved to favourites" : "Save favourite", systemImage: store.data.favourites.contains(recipe.id) ? "heart.fill" : "heart") }
                Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                if store.details(recipe).baseServings == nil {
                    Text("Source servings are not provided. Set the original servings in Recipe details before scaling quantities.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Recipe details & servings") { editing = true }
                if let minutes = store.details(recipe).minutes { Label("\(minutes) minutes · your estimate", systemImage: "clock") }
                Button("Add to meal plan", systemImage: "calendar.badge.plus") { planning = true }
            }
            Section("Ingredients") {
                ForEach(StockEngine.requirements(recipe, factor: factor), id: \.ingredient.id) { requirement in
                    HStack {
                        Image(systemName: StockEngine.satisfies(requirement, stock: store.data.groceries) ? "checkmark.circle.fill" : "circle").foregroundStyle(.green)
                        Text(requirement.ingredient.name.capitalized)
                        Spacer()
                        Text(requirement.ingredient.amount).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Text("Stock checks use the quantities you entered. Package sizes and ingredient forms are kept distinct. Check product labels for allergens and vegetarian suitability.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Shopping & alternatives") {
                if !missing.isEmpty {
                    Button("Add required items to shopping") { store.buy(missing); store.notice = "Ingredients added to shopping. They will count as stock after you purchase and move them to the pantry." }
                    Button { Task { await suggest() } } label: { if busy { ProgressView("Checking your pantry…") } else { Label("Find pantry substitutes", systemImage: "sparkles") } }.disabled(busy || !PantryIntelligence.available)
                } else { Text("No additional ingredients needed for these quantities.").foregroundStyle(.secondary) }
                if let error { Text(error).font(.caption) }
                ForEach(ideas.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 5) { Text("\(ideas[i].missingIngredient) → \(ideas[i].availableReplacement)").font(.headline); Text(ideas[i].explanation).font(.subheadline) }
                }
            }
            Section("Method") { Text(recipe.instructions).textSelection(.enabled) }
            Section("Nutrition") {
                let linked = recipe.ingredients.compactMap { ingredient in store.data.groceries.first { IngredientRules.key($0.name) == IngredientRules.key(ingredient.name) && $0.nutrition != nil } }
                if linked.isEmpty { Text("Link sourced nutrition facts from each pantry ingredient. Recipe totals need known weights and complete nutrition coverage.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(Array(Dictionary(grouping: linked, by: \.id).values.compactMap(\.first))) { grocery in
                    NavigationLink { GroceryDetail(id: grocery.id) } label: {
                        VStack(alignment: .leading) { Text(grocery.name.capitalized); Text(grocery.nutrition?.calories.map { "\(FoodAmount.number($0)) kcal / 100 g · USDA" } ?? "Energy not provided").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Cook & learn") {
                Toggle("Deduct measured ingredients from pantry", isOn: $deduct)
                Button("I cooked this meal", systemImage: "checkmark.seal") { confirmCooking = true }
                Picker("Your rating", selection: Binding(get: { store.data.ratings[recipe.id] ?? 0 }, set: { store.data.ratings[recipe.id] = $0; store.save() })) {
                    Text("Not rated").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                }
            }
            Section { Link("View original on TheMealDB", destination: URL(string: recipe.source)!) }
        }
        .navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
        .onAppear { servings = store.data.profile.householdSize }
        .sheet(isPresented: $planning) { PlanMealSheet(recipe: recipe, servings: servings) }
        .sheet(isPresented: $editing) { RecipeMetadataView(recipe: recipe) }
        .confirmationDialog("Record this cooked meal?", isPresented: $confirmCooking, titleVisibility: .visible) { Button("Record meal") { store.markCooked(recipe, servings: servings, deduct: deduct) } }
    }
    private func suggest() async {
        busy = true; error = nil; defer { busy = false }
        do {
            ideas = try await PantryIntelligence.substitutes(recipe: recipe, groceries: store.data.groceries.filter { $0.available && store.permitted($0.name) }, excludeEggs: store.data.excludeEggs, factor: factor, profile: store.data.profile)
            ideas = ideas.filter { store.permitted($0.availableReplacement) }
            if ideas.isEmpty { error = "No suitable pantry substitutions were found." }
        } catch { self.error = "Could not suggest substitutes: \(error.localizedDescription)" }
    }
}
struct RecipeMetadataView: View {
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    @State private var details = RecipeDetails()
    var body: some View {
        NavigationStack {
            Form {
                Section("Your recipe notes") {
                    Text("Enter information you know about this recipe. These values are your estimates, not facts supplied by the recipe library.").font(.caption).foregroundStyle(.secondary)
                    TextField("Original servings", value: $details.baseServings, format: .number).keyboardType(.numberPad)
                    TextField("Cooking time in minutes", value: $details.minutes, format: .number).keyboardType(.numberPad)
                    TextField("Cuisine", text: $details.cuisine)
                    TextField("Equipment, comma separated", text: $details.equipment)
                }
                Text("Volume estimates: teaspoon 5 ml, tablespoon 15 ml, cup 240 ml. No weight-to-volume conversion is assumed.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Recipe details").navigationBarTitleDisplayMode(.inline)
            .onAppear { details = store.details(recipe) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.data.recipeDetails[recipe.id] = details; store.data.planApproved = false; store.save(); dismiss() }.disabled((details.baseServings ?? 1) < 1 || (details.baseServings ?? 1) > 100 || (details.minutes ?? 1) < 1) }
            }
        }
    }
}

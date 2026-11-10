import SwiftUI

struct RecipesView: View {
    @Binding var showingGroceries: Bool
    @Environment(PantryStore.self) private var store
    @State private var search = ""
    @State private var favouritesOnly = false
    @State private var discover = true
    @State private var mealType = "All"
    @State private var addRecipe: Recipe?
    @State private var editRecipe: Recipe?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Meals for you", systemImage: "sparkles").font(.title2.bold()).foregroundStyle(.green)
                    Text(discover ? "Explore vegetarian recipes." : "Meals using ingredients in your pantry.").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Recipes", selection: $discover) { Text("From my pantry").tag(false); Text("Discover").tag(true) }.pickerStyle(.segmented)
                    if discover {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(["All"] + MealTypeEngine.choices, id: \.self) { type in
                                Button(type) { mealType = type }.buttonStyle(.bordered).tint(mealType == type ? .green : .gray)
                            } }
                        }
                        Text("Meal types are suggestions. You can adjust them in a recipe’s details.").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Favourites only", isOn: $favouritesOnly)
                }
                if discover {
                    Section("Indian chef recipes") {
                        Text("Explore detailed vegetarian recipes on the chef’s website.").font(.caption).foregroundStyle(.secondary)
                        Link("Dal palak · Dassana Amit", destination: URL(string: "https://www.vegrecipesofindia.com/palak-dal-spinach-dal/")!)
                        Link("Sambar · Dassana Amit", destination: URL(string: "https://www.vegrecipesofindia.com/sambhar-recipe-a-method-made-easy/")!)
                        Link("Kerala vegetable stew · Dassana Amit", destination: URL(string: "https://www.vegrecipesofindia.com/kerala-vegetable-stew-recipe/")!)
                        Link("More from Dassana’s Veg Recipes", destination: URL(string: "https://www.vegrecipesofindia.com/")!)
                    }
                }
                ForEach(store.recipes.filter { (!discover || mealType == "All" || MealTypeEngine.types($0, details: store.data.recipeDetails[$0.id]).contains(mealType)) && (discover || ($0.ingredients.contains { IngredientRules.has($0.name, in: store.data.groceries) })) && (!favouritesOnly || store.data.favourites.contains($0.id)) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.ingredients.contains { $0.name.localizedCaseInsensitiveContains(search) }) }) { recipe in
                    NavigationLink { RecipeDetail(recipe: recipe) } label: { RecipeCard(recipe: recipe) }
                        .swipeActions(edge: .trailing) { Button("Add to plan", systemImage: "calendar.badge.plus") { addRecipe = recipe }.tint(.green) }
                        .contextMenu { Button("Edit meal types") { editRecipe = recipe } }
                }
                if store.recipes.isEmpty {
                    ContentUnavailableView("No matching recipes", systemImage: "leaf", description: Text("Review your dietary restrictions or download more vegetarian recipes."))
                }
                Section {
                    Button { Task { await store.importRecipes() } } label: {
                        if store.importing { ProgressView(store.importStatus) } else { Label("Update recipe library", systemImage: "arrow.down.circle") }
                    }.disabled(store.importing)
                    Button("Update Indian vegetarian recipes") { Task { await store.importRecipes(indian: true) } }.disabled(store.importing)
                    Link("Indian vegetarian recipes · Dassana Amit", destination: URL(string: "https://www.vegrecipesofindia.com/")!)
                    Link("Indian vegetarian recipes · Sanjeev Kapoor", destination: URL(string: "https://www.sanjeevkapoor.com/course/main-course-vegetarian")!)
                    Link("Recipes provided by TheMealDB", destination: URL(string: "https://www.themealdb.com")!).font(.caption)
                }
            }.navigationTitle("Recipes").searchable(text: $search, prompt: "Find a meal or ingredient")
            .sheet(item: $addRecipe) { PlanMealSheet(recipe: $0, servings: store.data.profile.householdSize) }
            .sheet(item: $editRecipe) { RecipeMetadataView(recipe: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showingGroceries = true } label: { Label("Groceries", systemImage: "basket") } }
                ToolbarItem(placement: .topBarTrailing) { NavigationLink { ProfileView() } label: { Image(systemName: "person.crop.circle") } }
            }
        }
    }
}
struct RecipeCard: View {
    @Environment(PantryStore.self) private var store
    let recipe: Recipe
    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: recipe.image.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.green.opacity(0.10).overlay(Image(systemName: "leaf").foregroundStyle(.green)) }
                .frame(width: 104, height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title).font(.headline).foregroundStyle(.primary)
                Text("\(recipe.ingredients.count) ingredients").font(.subheadline).foregroundStyle(.secondary)
                if StockEngine.ready(recipe, stock: store.data.groceries) { Label("Ready to cook", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
            }
            Spacer(minLength: 0)
            if let minutes = store.details(recipe).minutes ?? recipe.sourceTotalMinutes { Label("\(minutes) min", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
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
    @State private var section = "Ingredients"
    @State private var guide: CookingGuide?
    @State private var guideBusy = false
    @State private var guideError: String?
    @State private var guideAttempted = false
    @State private var cookingPhase = "Prep"
    @State private var checked: Set<String> = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AsyncImage(url: recipe.image.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.green.opacity(0.10).overlay(Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.green)) }
                    .frame(height: 245).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Text(recipe.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button { store.toggleFavourite(recipe) } label: { Image(systemName: store.data.favourites.contains(recipe.id) ? "heart.fill" : "heart").font(.title2).foregroundStyle(.green) }.accessibilityLabel("Toggle favourite")
                    }
                    HStack(spacing: 14) {
                        Label("\(recipe.ingredients.count) ingredients", systemImage: "list.bullet")
                        if let total = store.details(recipe).minutes ?? recipe.sourceTotalMinutes { Label("\(total) min", systemImage: "clock") }
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if recipe.sourcePrepMinutes != nil || recipe.sourceCookMinutes != nil {
                        HStack {
                            if let prep = recipe.sourcePrepMinutes { Label("Prep \(prep) min", systemImage: "timer") }
                            if let cook = recipe.sourceCookMinutes { Label("Cook \(cook) min", systemImage: "flame") }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Recipe section", selection: $section) { Text("Ingredients").tag("Ingredients"); Text("Steps").tag("Steps"); Text("Notes").tag("Notes") }.pickerStyle(.segmented)
                    if section == "Ingredients" {
                        Text("Ingredients").font(.title2.bold())
                        ForEach(StockEngine.requirements(recipe, factor: factor), id: \.ingredient.id) { requirement in
                            Button {
                                let id = requirement.ingredient.id
                                if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: checked.contains(requirement.ingredient.id) ? "checkmark.square.fill" : "square").foregroundStyle(.green)
                                    Text(requirement.ingredient.name.capitalized).foregroundStyle(.primary)
                                    Spacer()
                                    Text(requirement.ingredient.amount).foregroundStyle(.secondary)
                                }.padding(.vertical, 5)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                        if !missing.isEmpty {
                            Button { Task { await suggest() } } label: { if busy { ProgressView("Checking your pantry…") } else { Label("Find pantry substitutes", systemImage: "sparkles") } }.disabled(busy || !PantryIntelligence.available)
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                        ForEach(ideas.indices, id: \.self) { i in Text("\(ideas[i].missingIngredient) → \(ideas[i].availableReplacement): \(ideas[i].explanation)") }
                    } else if section == "Steps" {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(.green)
                            VStack(alignment: .leading) { Text("Cooking guide").font(.title2.bold()); Text("Prep first, then cook step by step").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                        }
                        Picker("Cooking phase", selection: $cookingPhase) { Text("Prep").tag("Prep"); Text("Cooking").tag("Cooking") }.pickerStyle(.segmented)
                        if guideBusy { ProgressView("Preparing your cooking guide on this iPhone…") }
                        else if let guide {
                            Text("AI-organised guidance · check the original method below").font(.caption).foregroundStyle(.secondary)
                            let steps = cookingPhase == "Prep" ? guide.prep : guide.cooking
                            if steps.isEmpty { Text(cookingPhase == "Prep" ? "No separate prep steps were identified." : "No cooking steps were identified. Check the original method.").foregroundStyle(.secondary) }
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                CookingActionCard(index: index + 1, step: step, prep: cookingPhase == "Prep", source: recipe.instructions)
                            }
                            Button("Refresh AI guide", systemImage: "arrow.clockwise") { Task { await buildGuide() } }
                        } else {
                            if let guideError { Text(guideError).font(.caption).foregroundStyle(.secondary) }
                            Button("Create detailed guide", systemImage: "sparkles") { Task { await buildGuide() } }.disabled(!PantryIntelligence.available)
                            if !PantryIntelligence.available { Text(PantryIntelligence.status).font(.caption).foregroundStyle(.secondary) }
                        }
                        DisclosureGroup("Original recipe method") {
                            ForEach(Array(MethodSteps.extract(recipe.instructions).enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top) { Text("\(index + 1)").bold().foregroundStyle(.green); Text(step).textSelection(.enabled) }.padding(.vertical, 5)
                            }
                        }
                        Toggle("Deduct measured ingredients from pantry", isOn: $deduct)
                        Button("I cooked this meal", systemImage: "checkmark.seal") { confirmCooking = true }
                    } else {
                        Picker("Your rating", selection: Binding(get: { store.data.ratings[recipe.id] ?? 0 }, set: { store.data.ratings[recipe.id] = $0; store.save() })) {
                            Text("Not rated").tag(0); ForEach(1...5, id: \.self) { Text("\($0) / 5").tag($0) }
                        }
                        Text("Nutrition facts are available for pantry ingredients linked to USDA data.").font(.caption).foregroundStyle(.secondary)
                        ForEach(recipe.ingredients) { ingredient in
                            if let item = store.data.groceries.first(where: { IngredientRules.key($0.name) == IngredientRules.key(ingredient.name) && $0.nutrition != nil }) {
                                NavigationLink("\(ingredient.name.capitalized) nutrition") { GroceryDetail(id: item.id) }
                            }
                        }
                        if recipe.source == "mealplanner:original" { Text("Meal Planner original recipe") }
                        else if recipe.source == "mealplanner:personal" { Text("Your imported recipe · \(recipe.sourceFile ?? "Meals")") }
                        else if let url = URL(string: recipe.source), url.scheme == "https" { Link("View original recipe", destination: url) }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button { planning = true } label: { Label("Add to plan", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                if store.data.selectedRecipeIDs.contains(recipe.id) {
                    Button("Remove", systemImage: "checkmark.circle.fill") { store.removeSelectedRecipe(recipe) }.buttonStyle(.bordered)
                } else {
                    Button("Groceries", systemImage: "basket.badge.plus") { store.selectRecipe(recipe); store.notice = "Missing ingredients were added to Shopping." }.buttonStyle(.bordered)
                }
            }.controlSize(.large).padding(12).background(.regularMaterial)
        }
        .navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
        .onAppear { servings = store.details(recipe).baseServings ?? store.data.profile.householdSize }
        .onChange(of: section) { _, value in
            if value == "Steps", !guideAttempted, PantryIntelligence.available { Task { await buildGuide() } }
        }
        .sheet(isPresented: $planning) { PlanMealSheet(recipe: recipe, servings: servings) }
        .sheet(isPresented: $editing) { RecipeMetadataView(recipe: recipe) }
        .confirmationDialog("Record this cooked meal?", isPresented: $confirmCooking, titleVisibility: .visible) { Button("Record meal") { store.markCooked(recipe, servings: servings, deduct: deduct) } }
    }
    private func buildGuide() async {
        guard !guideBusy else { return }
        guideBusy = true; guideAttempted = true; guideError = nil
        defer { guideBusy = false }
        do {
            let generated = try await PantryIntelligence.cookingGuide(recipe: recipe)
            guard !generated.prep.isEmpty || !generated.cooking.isEmpty else { guideError = "No guide was returned. Please use the original method below."; return }
            guide = generated
        } catch { guideError = "Could not create the guide. The original method is available below." }
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
                    Section("Meal types") {
                        ForEach(MealTypeEngine.choices, id: \.self) { type in
                            Toggle(type, isOn: Binding(get: { (details.mealTypes ?? MealTypeEngine.types(recipe, details: nil)).contains(type) }, set: { enabled in
                                var selected = details.mealTypes ?? MealTypeEngine.types(recipe, details: nil)
                                if enabled && !selected.contains(type) { selected.append(type) }
                                if !enabled { selected.removeAll { $0 == type } }
                                details.mealTypes = selected
                            }))
                        }
                    }
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

struct CookingActionCard: View {
    let index: Int
    let step: CookingAction
    let prep: Bool
    let source: String
    func confirmed(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.localizedCaseInsensitiveCompare("Not specified") != .orderedSame && source.localizedCaseInsensitiveContains(trimmed)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: prep ? "hands.sparkles.fill" : "flame.fill").font(.title3).foregroundStyle(.green)
                Text("\(index)").font(.caption.bold()).foregroundStyle(.secondary)
            }.frame(width: 38)
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title).font(.headline)
                Text(step.action).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if !prep { Label(confirmed(step.heat) ? step.heat : "Heat not specified", systemImage: "flame") }
                    Label(confirmed(step.duration) ? step.duration : "Time not specified", systemImage: "clock")
                }.font(.caption).foregroundStyle(.secondary)
                if !step.cue.isEmpty, step.cue.localizedCaseInsensitiveCompare("Not specified") != .orderedSame { Label(step.cue, systemImage: "eye").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

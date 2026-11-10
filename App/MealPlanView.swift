import SwiftUI

struct MealPlanView: View {
    @Environment(PantryStore.self) private var store
    @State private var choosing = false
    @State private var shoppingPreview = false
    @State private var confirmDraft = false
    var days: [Date] { (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: store.data.planningStart)) } }
    var weekMeals: [PlannedMeal] { store.data.plans.filter { p in days.contains { Calendar.current.isDate($0, inSameDayAs: p.date) } } }
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    DatePicker("Week starts", selection: $store.data.planningStart, displayedComponents: .date).onChange(of: store.data.planningStart) { _, _ in store.data.planApproved = false; store.save() }
                    Stepper("Meals to draft: \(store.data.planningMealCount)", value: $store.data.planningMealCount, in: 1...21).onChange(of: store.data.planningMealCount) { _, _ in store.save() }
                    NavigationLink { ProfileView() } label: { Label("Household & preferences", systemImage: "person.2") }
                    Button("Draft a week for me", systemImage: "sparkles") { confirmDraft = true }
                    Text("Drafts use your preferences, history, restrictions, and any cooking time or equipment information you have entered. Review meals before approving.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(days, id: \.self) { date in
                    Section(date.formatted(.dateTime.weekday(.wide).month().day())) {
                        let meals = weekMeals.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.sorted { slotOrder($0.slot) < slotOrder($1.slot) }
                        if meals.isEmpty { Text("No meals planned").foregroundStyle(.secondary) }
                        ForEach(meals) { meal in
                            if let recipe = store.data.recipes.first(where: { $0.id == meal.recipeID }) {
                                NavigationLink { PlannedMealDetail(mealID: meal.id, recipe: recipe) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(meal.slot) · \(meal.servings) servings").font(.caption).foregroundStyle(.secondary)
                                        Text(recipe.title).font(.headline)
                                        if meal.completed { Label("Cooked", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                                        if !RecommendationEngine.allowed(recipe, data: store.data) { Text("Review: restrictions have changed").font(.caption).foregroundStyle(.orange) }
                                    }
                                }.swipeActions { Button("Remove", role: .destructive) { store.data.plans.removeAll { $0.id == meal.id }; store.data.planApproved = false; store.save() } }
                            }
                        }
                    }
                }
                if !weekMeals.isEmpty {
                    Section("Review your week") {
                        if store.data.planApproved { Label("Plan approved", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                        Button(store.data.planApproved ? "Review shopping ingredients" : "Approve plan & review shopping") { store.data.planApproved = true; store.save(); shoppingPreview = true }
                            .disabled(weekMeals.contains { meal in store.data.recipes.first(where: { $0.id == meal.recipeID }).map { !RecommendationEngine.allowed($0, data: store.data) } ?? true })
                    }
                }
            }.navigationTitle("Meal plan")
            .toolbar { Button("Add meal", systemImage: "plus") { choosing = true } }
            .sheet(isPresented: $choosing) { ChooseRecipeForPlan() }
            .sheet(isPresented: $shoppingPreview) { PlanShoppingPreview() }
            .confirmationDialog("Draft meals for this week?", isPresented: $confirmDraft, titleVisibility: .visible) {
                Button("Replace this week’s uncompleted meals") { store.generatePlan() }
            }
        }
    }
    private func slotOrder(_ slot: String) -> Int { ["Breakfast", "Lunch", "Dinner"].firstIndex(of: slot) ?? 3 }
}
struct ChooseRecipeForPlan: View {
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(store.recipes) { recipe in NavigationLink { PlanMealSheetContent(recipe: recipe, initialServings: store.data.profile.householdSize, onSaved: { dismiss() }) } label: { RecipeCard(recipe: recipe) } }
                .navigationTitle("Choose a meal").toolbar { Button("Done") { dismiss() } }
        }
    }
}
struct PlanMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let servings: Int
    var body: some View { NavigationStack { PlanMealSheetContent(recipe: recipe, initialServings: servings, onSaved: { dismiss() }) } }
}
struct PlanMealSheetContent: View {
    @Environment(PantryStore.self) private var store
    let recipe: Recipe
    let initialServings: Int
    let onSaved: () -> Void
    @State private var date = Date.now
    @State private var slot = "Dinner"
    @State private var servings = 1
    var body: some View {
        Form {
            Text(recipe.title).font(.headline)
            DatePicker("Day", selection: $date, displayedComponents: .date)
            Picker("Meal", selection: $slot) { ForEach(["Breakfast", "Lunch", "Dinner"], id: \.self) { Text($0) } }
            Stepper("Servings: \(servings)", value: $servings, in: 1...20)
            Text("Saving replaces any meal already in the same day and slot. Completed meals are kept in your history.").font(.caption).foregroundStyle(.secondary)
            Button("Save to plan") { store.plan(recipe, date: date, slot: slot, servings: servings); onSaved() }
        }.navigationTitle("Plan a meal").onAppear { servings = initialServings }
    }
}
struct PlannedMealDetail: View {
    @Environment(PantryStore.self) private var store
    let mealID: UUID
    let recipe: Recipe
    @State private var swapping = false
    @State private var confirm = false
    @State private var deduct = true
    var meal: PlannedMeal? { store.data.plans.first { $0.id == mealID } }
    var body: some View {
        List {
            if let meal {
                Section {
                    Text(recipe.title).font(.title2.bold())
                    Text("\(meal.date.formatted(date: .abbreviated, time: .omitted)) · \(meal.slot)")
                    Stepper("Servings: \(meal.servings)", value: Binding(get: { self.meal?.servings ?? 1 }, set: { value in if let i = store.data.plans.firstIndex(where: { $0.id == mealID }) { store.data.plans[i].servings = value; store.data.planApproved = false; store.save() } }), in: 1...20).disabled(meal.completed)
                    NavigationLink("Open recipe") { RecipeDetail(recipe: recipe) }
                    if !meal.completed {
                        Button("Swap this meal") { swapping = true }
                        Toggle("Deduct measured ingredients", isOn: $deduct)
                        Button("Mark cooked") { confirm = true }.disabled(!RecommendationEngine.allowed(recipe, data: store.data))
                    } else { Label("Cooked and recorded", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
        }.navigationTitle("Planned meal")
        .sheet(isPresented: $swapping) {
            NavigationStack {
                List(store.recipes) { candidate in
                    Button(candidate.title) {
                        if let i = store.data.plans.firstIndex(where: { $0.id == mealID }) {
                            store.data.plans[i].recipeID = candidate.id
                            store.data.planApproved = false
                            store.save()
                        }
                        swapping = false
                    }
                }
                .navigationTitle("Swap meal")
                .toolbar { Button("Cancel") { swapping = false } }
            }
        }
        .confirmationDialog("Record this meal as cooked?", isPresented: $confirm, titleVisibility: .visible) { Button("Record cooked meal") { if let meal { store.markCooked(recipe, servings: meal.servings, deduct: deduct, planID: mealID) } } }
    }
}
struct PlanShoppingPreview: View {
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Text("Ingredients are combined across the week, then measured stock is deducted once. Review unknown package sizes and amounts before adding.").font(.caption).foregroundStyle(.secondary)
                let unscaled = store.unscaledPlanRecipes()
                if !unscaled.isEmpty {
                    Section("Original servings needed") {
                        Text("The recipe source does not provide serving counts. Enter original servings for these recipes so the shopping list can be scaled accurately.").font(.caption).foregroundStyle(.secondary)
                        ForEach(unscaled) { recipe in NavigationLink(recipe.title) { RecipeMetadataView(recipe: recipe) } }
                    }
                }
                let needed = unscaled.isEmpty ? store.planShopping() : []
                if needed.isEmpty && unscaled.isEmpty { ContentUnavailableView("Your pantry covers this plan", systemImage: "checkmark.basket", description: Text("Check amounts and product labels before cooking.")) }
                ForEach(needed) { item in LabeledContent(item.name.capitalized, value: item.amount) }
                if !needed.isEmpty { Button("Add these ingredients to shopping") { store.buy(needed); dismiss() } }
            }.navigationTitle("Plan shopping").toolbar { Button("Done") { dismiss() } }
        }
    }
}

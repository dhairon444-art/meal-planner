import SwiftUI

struct MealPlanView: View {
    @Environment(PantryStore.self) private var store
    @State private var selectedDate = Date.now
    @State private var choosing = false
    @State private var chosenSlot = "Dinner"
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Choose a day", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden()
                }
                ForEach(["Breakfast", "Lunch", "Dinner"], id: \.self) { slot in
                    Section(slot == "Breakfast" ? "Morning" : slot == "Lunch" ? "Afternoon" : "Evening") {
                        if let meal = store.data.plans.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) && $0.slot == slot }), let recipe = store.data.recipes.first(where: { $0.id == meal.recipeID }) {
                            NavigationLink { PlannedMealDetail(mealID: meal.id, recipe: recipe) } label: {
                                AsyncImage(url: recipe.image.flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Color.green.opacity(0.1).overlay(Image(systemName: "fork.knife").font(.title)) }
                                    .frame(height: 155).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            }.accessibilityLabel("\(slot): \(recipe.title)")
                        } else {
                            Button { chosenSlot = slot; choosing = true } label: {
                                RoundedRectangle(cornerRadius: 14).fill(Color.green.opacity(0.08)).frame(height: 110).overlay(Image(systemName: "plus.circle").font(.title).foregroundStyle(.green))
                            }.buttonStyle(.plain).accessibilityLabel("Add \(slot)")
                        }
                    }
                }
            }.navigationTitle("Plan")
            .sheet(isPresented: $choosing) { ChooseRecipeForPlan(initialDate: selectedDate, initialSlot: chosenSlot) }
        }
    }
}
struct ChooseRecipeForPlan: View {
    var initialDate: Date = .now
    var initialSlot = "Dinner"
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(store.recipes) { recipe in NavigationLink { PlanMealSheetContent(recipe: recipe, initialServings: store.data.profile.householdSize, initialDate: initialDate, initialSlot: initialSlot, onSaved: { dismiss() }) } label: { RecipeCard(recipe: recipe) } }
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
    var initialDate: Date = .now
    var initialSlot = "Dinner"
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
        }.navigationTitle("Plan a meal").onAppear { servings = initialServings; date = initialDate; slot = initialSlot }
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

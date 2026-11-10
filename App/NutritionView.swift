import SwiftUI

struct GroceryDetail: View {
    @Environment(PantryStore.self) private var store
    let id: UUID
    @State private var results: [Nutrition] = []
    @State private var busy = false
    @State private var error: String?
    var grocery: Grocery? { store.data.groceries.first { $0.id == id } }
    var body: some View {
        Form {
            if let grocery {
                Section("Ingredient") {
                    Text(grocery.name.capitalized).font(.title2.bold())
                    TextField("Quantity, e.g. 500 g", text: Binding(get: { self.grocery?.quantity ?? "" }, set: { value in edit { $0.quantity = value } }))
                    Toggle("In stock", isOn: Binding(get: { self.grocery?.inStock != false }, set: { value in edit { $0.inStock = value } }))
                    Toggle("Track use-by date", isOn: Binding(get: { self.grocery?.expiry != nil }, set: { value in edit { $0.expiry = value ? .now : nil } }))
                    if grocery.expiry != nil { DatePicker("Use by", selection: Binding(get: { self.grocery?.expiry ?? .now }, set: { value in edit { $0.expiry = value } }), displayedComponents: .date) }
                    Text(grocery.category).foregroundStyle(.secondary)
                }
                if let nutrition = grocery.nutrition {
                    Section("Nutrition · per 100 g") {
                        Text(nutrition.description).font(.caption)
                        nutrient("Energy", value: nutrition.calories, unit: "kcal")
                        nutrient("Protein", value: nutrition.protein, unit: "g")
                        nutrient("Carbohydrates", value: nutrition.carbs, unit: "g")
                        nutrient("Fat", value: nutrition.fat, unit: "g")
                        Link("USDA FoodData Central · source", destination: URL(string: "https://fdc.nal.usda.gov/food-details/\(nutrition.sourceID)/nutrients")!)
                        Button("Remove nutrition match", role: .destructive) { update(nil) }
                    }
                }
                Section("Find nutrition facts") {
                    Text("Choose the matching food and preparation, such as raw versus cooked. Generic food data is an estimate for your ingredient, not its exact product label.").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await search(grocery.name) } } label: {
                        if busy { ProgressView("Searching USDA…") } else { Label("Search nutrition library", systemImage: "magnifyingglass") }
                    }.disabled(busy)
                    if let error { Text(error).foregroundStyle(.red) }
                    ForEach(results, id: \.sourceID) { result in
                        Button { update(result); results = [] } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(result.description)
                                Text("Tap to confirm this food match").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Ingredient").navigationBarTitleDisplayMode(.inline)
    }
    private func edit(_ change: (inout Grocery) -> Void) {
        if let i = store.data.groceries.firstIndex(where: { $0.id == id }) { change(&store.data.groceries[i]); store.save() }
    }
    private func nutrient(_ title: String, value: Double?, unit: String) -> some View {
        HStack { Text(title); Spacer(); Text(value.map { String(format: "%.1f %@", $0, unit) } ?? "Not provided").foregroundStyle(.secondary) }
    }
    private func update(_ nutrition: Nutrition?) {
        if let index = store.data.groceries.firstIndex(where: { $0.id == id }) { store.data.groceries[index].nutrition = nutrition; store.save() }
    }
    private func search(_ query: String) async {
        busy = true; error = nil
        defer { busy = false }
        do { results = try await OnlineLibrary.nutrition(query: query); if results.isEmpty { error = "No matches found. Nutrition remains unknown." } }
        catch { self.error = error.localizedDescription }
    }
}

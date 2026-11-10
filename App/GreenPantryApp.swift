import SwiftUI
import PhotosUI
import UIKit

@main struct GreenPantryApp: App {
    @State private var store = PantryStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(.green)
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
        }
    }
}

struct RootView: View {
    @Environment(PantryStore.self) private var store
    @State private var selection = 1
    @State private var showShopping = false
    @State private var showingGroceries = false
    var body: some View {
        @Bindable var store = store
        TabView(selection: $selection) {
            Tab("Recipes", systemImage: "book.closed.fill", value: 1) { RecipesView(showingGroceries: $showingGroceries) }
            Tab("Plan", systemImage: "calendar", value: 4) { MealPlanView() }
            Tab("Settings", systemImage: "gearshape", value: 3) { SettingsView() }
        }
        .onOpenURL { url in
            if url.scheme == "greenpantry" { showShopping = url.host == "shopping"; selection = url.host == "settings" ? 3 : 1; showingGroceries = url.host == "shopping" }
        }
        .sheet(isPresented: $showingGroceries) { GroceriesView(shopping: $showShopping) }
        .alert("Meal Planner", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }
}

struct GroceriesView: View {
    @Environment(PantryStore.self) private var store
    @Binding var shopping: Bool
    @State private var entry = ""
    @State private var addingPhoto = false
    @State private var editing: ShoppingItem?
    @State private var quantityTarget: QuantityTarget?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("List", selection: $shopping) { Text("Pantry").tag(false); Text("Shopping").tag(true) }.pickerStyle(.segmented)
                    HStack {
                        Image(systemName: "circle").foregroundStyle(.secondary)
                        TextField(shopping ? "Add a shopping item" : "Add an ingredient", text: $entry)
                            .focused($focused).submitLabel(.done).onSubmit(add)
                    }
                }
                if shopping {
                    ForEach(store.data.shopping) { item in
                        HStack {
                            Button { if let i = store.data.shopping.firstIndex(where: { $0.id == item.id }) { store.data.shopping[i].purchased.toggle(); store.save() } } label: { Image(systemName: item.purchased ? "checkmark.circle.fill" : "circle").foregroundStyle(.green) }.buttonStyle(.borderless)
                            Button { editing = item } label: { HStack { Text(item.name.capitalized).strikethrough(item.purchased); Spacer(); Text(item.quantity).foregroundStyle(.secondary) }.contentShape(Rectangle()) }.buttonStyle(.plain)
                        }.swipeActions { Button("Delete", role: .destructive) { store.data.shopping.removeAll { $0.id == item.id }; store.save() } }
                    }
                    if store.data.shopping.contains(where: \.purchased) { Button("Move purchased items to pantry") { store.movePurchased() } }
                } else {
                    ForEach(store.data.groceries) { item in
                        NavigationLink { GroceryDetail(id: item.id) } label: {
                            HStack { Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(item.available ? .green : .gray); Text(item.name.capitalized); Spacer(); Text(item.quantity).foregroundStyle(.secondary) }
                        }.swipeActions { Button("Delete", role: .destructive) { store.data.groceries.removeAll { $0.id == item.id }; store.save() } }
                    }
                }
            }
            .navigationTitle("Groceries")
            .toolbar { Button("Add from photo", systemImage: "plus") { addingPhoto = true } }
            .sheet(isPresented: $addingPhoto) { AddGroceriesView(initialInStock: !shopping, photoOnly: true) }
            .sheet(item: $editing) { ShoppingItemEditor(item: $0) }
            .sheet(item: $quantityTarget) { target in
                QuantityWheel(name: target.name) { quantity in
                    if target.shopping, let index = store.data.shopping.firstIndex(where: { $0.id == target.id }) { store.data.shopping[index].quantity = quantity; store.save() }
                    else if !target.shopping, let index = store.data.groceries.firstIndex(where: { $0.id == target.id }) { store.data.groceries[index].quantity = quantity; store.save() }
                }
            }
        }
    }
    private func add() {
        let name = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard store.permitted(name) else { store.notice = "This ingredient conflicts with your dietary restrictions."; return }
        if shopping {
            let item = ShoppingItem(name: name, quantity: "")
            store.data.shopping.append(item); store.save()
            quantityTarget = QuantityTarget(id: item.id, name: name, shopping: true)
        }
        else {
            let item = Grocery(name: name, quantity: "", category: "Other")
            store.add([item])
            quantityTarget = QuantityTarget(id: item.id, name: name, shopping: false)
            Task {
                if PantryIntelligence.available, let parsed = try? await PantryIntelligence.parse(name), let category = parsed.first?.category,
                   ["Produce", "Grains", "Pulses", "Dairy", "Eggs", "Nuts & seeds", "Condiments", "Other"].contains(category),
                   let index = store.data.groceries.firstIndex(where: { $0.id == item.id }) {
                    if store.data.groceries[index].name == name, let result = parsed.first, store.permitted(result.name) {
                        store.data.groceries[index].name = result.name
                        if store.data.groceries[index].quantity.isEmpty { store.data.groceries[index].quantity = result.quantity }
                    }
                    store.data.groceries[index].category = category
                    store.save()
                }
            }
        }
        entry = ""
        focused = false
    }
}

struct AddGroceriesView: View {
    var initialInStock = true
    var photoOnly = false
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var manual = false
    @State private var name = ""
    @State private var quantity = ""
    @State private var category = "Produce"
    @State private var draft: [Grocery] = []
    @State private var candidates: [UUID: [Nutrition]] = [:]
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var imageBusy = false
    @State private var addToStock = true
    @State private var busy = false
    @State private var error: String?
    let categories = ["Produce", "Grains", "Pulses", "Dairy", "Eggs", "Nuts & seeds", "Condiments", "Other"]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Vegetarian ingredients only", systemImage: "leaf").foregroundStyle(.green)
                    Text(PantryIntelligence.status).font(.caption).foregroundStyle(.secondary)
                    Toggle("I already have these items", isOn: $addToStock)
                    Text(addToStock ? "Save to in-stock pantry." : "Save to shopping only. Items will not count as in stock.").font(.caption).foregroundStyle(.secondary)
                    if !photoOnly { Toggle("Enter one item manually", isOn: $manual) }
                }
                Section("Add from a photo") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose a photo", systemImage: "photo") }.disabled(imageBusy || busy)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take a photo", systemImage: "camera") { camera = true }.disabled(imageBusy || busy)
                    }
                    if imageBusy { ProgressView("Reading your image on this iPhone…") }
                    Text("Use a receipt, label, grocery list, or clearly visible food. Review extracted text and suggestions; photo recognition can miss items. Photos stay on your phone.").font(.caption).foregroundStyle(.secondary)
                }
                if !photoOnly && (manual || !PantryIntelligence.available) {
                    Section("Ingredient") {
                        TextField("Ingredient name", text: $name)
                        TextField("Quantity, e.g. 500 g", text: $quantity)
                        Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }
                        Button("Add to review") {
                            let item = Grocery(name: name.trimmingCharacters(in: .whitespacesAndNewlines), quantity: quantity, category: category)
                            draft.append(item); name = ""; quantity = ""
                            Task { await findNutrition(for: item) }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else if !photoOnly || !text.isEmpty {
                    Section("What did you bring home?") {
                        TextEditor(text: $text).frame(minHeight: 110)
                        Text("Try: 2 tins chickpeas, 500 g tomatoes, basmati rice and Greek yoghurt. Nutrition lookup sends ingredient names to USDA.").font(.caption).foregroundStyle(.secondary)
                        Button { Task { await organize() } } label: {
                            if busy { ProgressView("Organizing and finding nutrition…") } else { Label("Organize with Apple Intelligence", systemImage: "sparkles") }
                        }.disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !text.isEmpty && (manual || !PantryIntelligence.available) {
                    Section("Recognized text") { TextEditor(text: $text).frame(minHeight: 100) }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !draft.isEmpty {
                    Section("Review before saving") {
                        ForEach($draft) { $item in
                            VStack {
                                TextField("Ingredient", text: $item.name)
                                TextField("Quantity", text: $item.quantity).font(.caption)
                                Picker("Category", selection: $item.category) { ForEach(categories, id: \.self) { Text($0) } }
                                if let matches = candidates[item.id], !matches.isEmpty {
                                    Picker("Nutrition match", selection: Binding<Int>(get: { item.nutrition?.sourceID ?? 0 }, set: { selected in item.nutrition = matches.first { $0.sourceID == selected } })) {
                                        Text("Choose a food match").tag(0)
                                        ForEach(matches, id: \.sourceID) { Text($0.description).tag($0.sourceID) }
                                    }
                                    Text("Per 100 g from USDA. Confirm raw/cooked state and type.").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("Nutrition not linked yet. You can search from the saved ingredient.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.onDelete { draft.remove(atOffsets: $0) }
                    }
                }
            }
            .onAppear { addToStock = initialInStock }
            .sheet(isPresented: $camera) { CameraCapture { data in Task { await readImage(data) } } }
            .onChange(of: photo) { _, item in Task {
                do { if let data = try await item?.loadTransferable(type: Data.self) { await readImage(data) } }
                catch { self.error = "Could not load that photo. Try another image." }
            } }
            .navigationTitle("Add groceries").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(draft.isEmpty || busy || imageBusy) }
            }
        }
    }
    private func readImage(_ image: Data) async {
        imageBusy = true; error = nil
        defer { imageBusy = false }
        do {
            let vocabulary = store.data.recipes.flatMap { $0.ingredients.map(\.name) } + ["apple", "banana", "orange", "carrot", "potato", "tomato", "broccoli", "spinach", "rice", "lentil", "milk", "yoghurt"]
            let result = try await GroceryImageReader.read(image, vocabulary: vocabulary)
            if !result.text.isEmpty {
                text = result.text
                manual = false
                if !PantryIntelligence.available {
                    draft = result.text.split(separator: "\n").map { Grocery(name: String($0), quantity: "", category: "Other") }
                    error = "Review and remove any lines that are not groceries."
                }
            } else if !result.candidates.isEmpty {
                draft = result.candidates.map { Grocery(name: $0, quantity: "", category: "Other") }
            } else { error = "No readable ingredients were found. Try a clearer receipt or label, or type your items." }
        } catch { self.error = "Could not read this image: \(error.localizedDescription)" }
    }
    private func organize() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            draft = try await PantryIntelligence.parse(text)
            for item in draft.prefix(10) { await findNutrition(for: item) }
        }
        catch { self.error = "Could not organize these groceries. You can switch to manual entry. \(error.localizedDescription)" }
    }
    private func findNutrition(for item: Grocery) async {
        guard IngredientRules.isVegetarian(item.name) else { return }
        do { candidates[item.id] = try await OnlineLibrary.nutrition(query: item.name) }
        catch { self.error = "Groceries are ready to save. Nutrition lookup was unavailable: \(error.localizedDescription)" }
    }
    private func save() {
        guard draft.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.permitted($0.name) }) else {
            error = "Please remove empty names or ingredients that conflict with your dietary restrictions."; return
        }
        if addToStock { store.add(draft) }
        else { store.buy(draft.map { Ingredient(name: $0.name, amount: $0.quantity) }) }
        dismiss()
    }
}

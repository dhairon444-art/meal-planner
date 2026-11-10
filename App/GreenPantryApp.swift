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
    @State private var selection = 0
    var body: some View {
        @Bindable var store = store
        TabView(selection: $selection) {
            Tab("Pantry", systemImage: "carrot.fill", value: 0) { PantryView() }
            Tab("Recipes", systemImage: "book.closed.fill", value: 1) { RecipesView() }
            Tab("Plan", systemImage: "calendar", value: 4) { MealPlanView() }
            Tab("Shopping", systemImage: "basket.fill", value: 2) { ShoppingView() }
            Tab("Settings", systemImage: "gearshape", value: 3) { SettingsView() }
        }
        .onOpenURL { url in
            if url.scheme == "greenpantry" { selection = url.host == "shopping" ? 2 : url.host == "settings" ? 3 : 1 }
        }
        .alert("Meal Planner", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: { Text(store.notice ?? "") }
    }
}

struct PantryView: View {
    @Environment(PantryStore.self) private var store
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Good food starts here", systemImage: "leaf.fill").font(.title2.bold()).foregroundStyle(.green)
                        Text("Add what you have. Discover what you can make.").foregroundStyle(.secondary)
                        Text("\(store.data.groceries.filter(\.available).count) in stock · Vegetarian").font(.caption.bold())
                    }.padding(.vertical, 14)
                }
                if store.data.groceries.isEmpty {
                    ContentUnavailableView("Your pantry is ready", systemImage: "carrot", description: Text("Tap + to add a few ingredients in your own words."))
                }
                ForEach(Array(Set(store.data.groceries.map(\.category))).sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(store.data.groceries.filter { $0.category == category }) { grocery in
                            NavigationLink { GroceryDetail(id: grocery.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(grocery.name.capitalized).font(.headline)
                                    Text(grocery.quantity.isEmpty ? "Quantity not set" : grocery.quantity).font(.subheadline).foregroundStyle(.secondary)
                                    if !grocery.available { Text("Not in stock").font(.caption).foregroundStyle(.secondary) }
                                    if let expiry = grocery.expiry { Text("Use by \(expiry.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.orange) }
                                    if grocery.nutrition != nil { Label("Nutrition linked", systemImage: "checkmark.seal").font(.caption).foregroundStyle(.green) }
                                }.padding(.vertical, 3)
                            }.swipeActions { Button("Delete", role: .destructive) { store.data.groceries.removeAll { $0.id == grocery.id }; store.save() } }
                        }
                    }
                }
            }
            .navigationTitle("My pantry")
            .toolbar { Button("Add groceries", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { AddGroceriesView() }
        }
    }
}

struct AddGroceriesView: View {
    var initialInStock = true
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
                    Toggle("Enter one item manually", isOn: $manual)
                }
                Section("Add from a photo") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose a photo", systemImage: "photo") }.disabled(imageBusy || busy)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take a photo", systemImage: "camera") { camera = true }.disabled(imageBusy || busy)
                    }
                    if imageBusy { ProgressView("Reading your image on this iPhone…") }
                    Text("Use a receipt, label, grocery list, or clearly visible food. Review extracted text and suggestions; photo recognition can miss items. Photos stay on your phone.").font(.caption).foregroundStyle(.secondary)
                }
                if manual || !PantryIntelligence.available {
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
                } else {
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
                if !PantryIntelligence.available { error = "Text was recognized. Copy individual ingredients below, or enable Apple Intelligence to organize the text." }
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

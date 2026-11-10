import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(PantryStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section("Your household") {
                TextField("Name", text: $store.data.profile.name)
                Stepper("People: \(store.data.profile.householdSize)", value: $store.data.profile.householdSize, in: 1...20)
                Picker("Cooking confidence", selection: $store.data.profile.cookingConfidence) { ForEach(["Learning", "Comfortable", "Experienced"], id: \.self) { Text($0) } }
            }
            Section("Tastes · shape your recommendations") {
                TextField("Favourite ingredients, comma separated", text: $store.data.profile.preferredIngredients, axis: .vertical)
                TextField("Favourite cuisines, comma separated", text: $store.data.profile.preferredCuisines, axis: .vertical)
                TextField("Disliked ingredients, comma separated", text: $store.data.profile.dislikes, axis: .vertical)
                Text("Taste preferences influence ranking. Allergies and exclusions below filter recipes out.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Diet & ingredient restrictions") {
                Label("Vegetarian recipes only", systemImage: "leaf.fill").foregroundStyle(.green)
                Toggle("Exclude eggs", isOn: $store.data.excludeEggs)
                Toggle("Exclude dairy ingredients", isOn: $store.data.profile.dairyFree)
                ForEach(IngredientRules.allergyNames, id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { store.data.profile.allergens.contains(name) }, set: { enabled in
                        if enabled { store.data.profile.allergens.append(name) } else { store.data.profile.allergens.removeAll { $0 == name } }
                    }))
                }
                TextField("Other ingredients to exclude, comma separated", text: $store.data.profile.avoidIngredients, axis: .vertical)
                Text("Filters check named ingredients and known aliases. Recipe sources do not certify allergens, cross-contact, or product manufacturing; check labels for your needs.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Planning preferences") {
                TextField("Maximum cooking minutes (optional)", value: $store.data.profile.maxCookingMinutes, format: .number).keyboardType(.numberPad)
                TextField("Equipment you have, comma separated", text: $store.data.profile.equipment, axis: .vertical)
                Text("Time and equipment information can be entered in Recipe details.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Profile")
        .onChange(of: store.data.profile) { _, _ in store.data.planApproved = false; store.save() }
        .onChange(of: store.data.excludeEggs) { _, _ in store.data.planApproved = false; store.save() }
    }
}
struct HistoryView: View {
    @Environment(PantryStore.self) private var store
    var body: some View {
        List {
            Section {
                LabeledContent("Meals cooked", value: String(store.data.history.count))
                LabeledContent("Favourite recipes", value: String(store.data.favourites.count))
                Text("Cooking history and feedback improve your meal suggestions. These counts do not estimate food waste or health outcomes.").font(.caption).foregroundStyle(.secondary)
            }
            if store.data.history.isEmpty { ContentUnavailableView("Your cooking story starts here", systemImage: "fork.knife", description: Text("Open a recipe or planned meal and record it after cooking.")) }
            ForEach(store.data.history.sorted { $0.date > $1.date }) { event in
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title).font(.headline)
                    Text("\(event.servings) servings · \(event.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    if let recipe = store.data.recipes.first(where: { $0.id == event.recipeID }) { NavigationLink("View recipe") { RecipeDetail(recipe: recipe) } }
                }.swipeActions { Button("Remove history entry", role: .destructive) { store.data.history.removeAll { $0.id == event.id }; store.save() } }
            }
        }.navigationTitle("Cooking history")
    }
}
struct PantryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @Environment(PantryStore.self) private var store
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingBackup: PantryData?
    @State private var restoreConfirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Planner") {
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    NavigationLink("Profile, preferences & restrictions") { ProfileView() }
                    NavigationLink("Cooking history & progress") { HistoryView() }
                }
                Section("On-device intelligence") { Text(PantryIntelligence.status) }
                Section("Widgets") { Text("Touch and hold your Home Screen, choose Edit → Add Widget, then find Meal Planner. Shopping and recommendation widgets open the matching app screen. Recommendations follow your tastes; stock only controls the Ready to cook badge.") }
                Section("Backups") {
                    Button("Export backup", systemImage: "square.and.arrow.up") { exporting = true }
                    Button("Restore backup", systemImage: "square.and.arrow.down") { importing = true }
                    Text("Backups include your pantry, preferences, meal plans, shopping list and cooking history. Keep a copy before deleting the app.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy & sources") {
                    Text("Photos, pantry, profile and cooking history stay on this device. Apple Intelligence runs on-device. Nutrition lookup sends ingredient names to USDA; recipe downloads contact TheMealDB.")
                    Link("TheMealDB recipes", destination: URL(string: "https://www.themealdb.com/api.php")!)
                    Link("USDA FoodData Central nutrition", destination: URL(string: "https://fdc.nal.usda.gov")!)
                    Text("Nutrition values are sourced per 100 g. This development build uses rate-limited demo access. The app does not assign health ratings to recipes.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
            .fileExporter(isPresented: $exporting, document: PantryBackupDocument(data: (try? JSONEncoder().encode(store.data)) ?? Data()), contentType: .json, defaultFilename: "Meal-Planner-Backup") { result in if case .failure(let error) = result { store.notice = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let raw = try Data(contentsOf: url)
                    guard raw.count < 20_000_000 else { throw LibraryError(message: "This backup is too large.") }
                    guard let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any], object["groceries"] is [[String: Any]], object["recipes"] is [[String: Any]] else { throw LibraryError(message: "This file is not a Meal Planner backup.") }
                    let backup = try JSONDecoder().decode(PantryData.self, from: raw)
                    guard backup.recipes.allSatisfy({ $0.ingredients.allSatisfy { IngredientRules.isVegetarian($0.name) } }), backup.profile.householdSize >= 1, backup.profile.householdSize <= 20 else { throw LibraryError(message: "This file is not a valid vegetarian Meal Planner backup.") }
                    pendingBackup = backup; restoreConfirmation = true
                } catch { store.notice = "Could not read that backup: \(error.localizedDescription)" }
            }
            .confirmationDialog("Replace current data with this backup?", isPresented: $restoreConfirmation, titleVisibility: .visible) {
                Button("Restore \(pendingBackup?.groceries.count ?? 0) pantry items and saved plans", role: .destructive) {
                    if let backup = pendingBackup { store.data = backup; store.readOnly = false; store.save(); pendingBackup = nil }
                }
                Button("Cancel", role: .cancel) { pendingBackup = nil }
            }
        }
    }
}

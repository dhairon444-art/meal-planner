import SwiftUI

struct ShoppingView: View {
    @Environment(PantryStore.self) private var store
    @State private var adding = false
    @State private var editing: ShoppingItem?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Buy only what you need", systemImage: "basket.fill").font(.headline).foregroundStyle(.green)

                }
                if store.data.shopping.isEmpty { ContentUnavailableView("Your shopping list is clear", systemImage: "basket", description: Text("Add items by photo or typing, or generate ingredients from your meal plan.")) }
                ForEach(store.data.shopping) { item in
                    HStack {
                        Button { if let i = store.data.shopping.firstIndex(where: { $0.id == item.id }) { store.data.shopping[i].purchased.toggle(); store.save() } } label: { Image(systemName: item.purchased ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(.green) }.buttonStyle(.borderless).accessibilityLabel(item.purchased ? "Mark \(item.name) not purchased" : "Mark \(item.name) purchased")
                        Button { editing = item } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name.capitalized).strikethrough(item.purchased).foregroundStyle(.primary)
                                Text(item.quantity.isEmpty ? "Amount not set" : item.quantity).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderless)
                    }.swipeActions { Button("Delete", role: .destructive) { store.data.shopping.removeAll { $0.id == item.id }; store.save() } }
                }
                if store.data.shopping.contains(where: \.purchased) {
                    Section { Button("Move purchased items into stock", systemImage: "arrow.right.circle") { store.movePurchased() } }
                }
            }.navigationTitle("Shopping")
            .toolbar { Button("Add groceries", systemImage: "plus") { adding = true } }
            .sheet(isPresented: $adding) { AddGroceriesView(initialInStock: false) }
            .sheet(item: $editing) { item in ShoppingItemEditor(item: item) }
        }
    }
}
struct ShoppingItemEditor: View {
    @Environment(PantryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var item: ShoppingItem
    var body: some View {
        NavigationStack {
            Form {
                TextField("Ingredient", text: $item.name)
                TextField("Quantity, e.g. 500 g", text: $item.quantity)
                Toggle("Purchased", isOn: $item.purchased)
            }.navigationTitle("Shopping item").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard store.permitted(item.name) else { store.notice = "This item conflicts with your dietary restrictions."; return }
                    if let i = store.data.shopping.firstIndex(where: { $0.id == item.id }) { store.data.shopping[i] = item; store.save() }; dismiss()
                }.disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}

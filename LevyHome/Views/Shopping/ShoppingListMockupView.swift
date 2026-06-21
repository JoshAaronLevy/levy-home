import SwiftUI

struct ShoppingListMockupView: View {
    @State private var searchText = ""
    @State private var selectedCategory: ShoppingListCategory?
    @State private var items = ShoppingListItem.samples
    @State private var isShowingAddItem = false
    @State private var draftName = ""
    @State private var draftQuantity = 1
    @State private var draftCategory: ShoppingListCategory = .produce

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
                summaryPanel

                ShoppingListSearchField(searchText: $searchText)

                ShoppingCategoryFilterBar(
                    selectedCategory: $selectedCategory,
                    counts: categoryCounts
                )

                if groupedItems.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedItems) { group in
                        ShoppingCategorySection(
                            group: group,
                            onToggleCompleted: toggleCompleted,
                            onIncrementQuantity: incrementQuantity,
                            onDecrementQuantity: decrementQuantity
                        )
                    }
                }
            }
            .padding(AppSpacing.screen)
        }
        .background(AppColors.pageBackground)
        .navigationTitle("Shopping")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add shopping item")
            }
        }
        .sheet(isPresented: $isShowingAddItem) {
            addItemSheet
        }
    }

    private var summaryPanel: some View {
        InfoPanel(
            title: "Grocery List",
            subtitle: "\(plannedItemCount) items planned",
            systemImage: "cart"
        ) {
            HStack(spacing: AppSpacing.medium) {
                StatusBadgeView(label: "Shared", systemImage: "person.2", tone: .accent)
                StatusBadgeView(label: "\(completedItemCount) picked up", systemImage: "checkmark.circle", tone: .success)

                Spacer(minLength: 0)
            }
        }
    }

    private var emptyState: some View {
        InfoPanel(
            title: "No Matching Items",
            subtitle: "Try a product name or category.",
            systemImage: "magnifyingglass"
        ) {
            Button {
                searchText = ""
                selectedCategory = nil
            } label: {
                Label("Clear Filter", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
    }

    private var addItemSheet: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Product name", text: $draftName)

                    Stepper(value: $draftQuantity, in: 1...99) {
                        Text("Quantity \(draftQuantity)")
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $draftCategory) {
                        ForEach(ShoppingListCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetDraft()
                        isShowingAddItem = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addDraftItem()
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var groupedItems: [ShoppingCategoryGroup] {
        let itemsByCategory = Dictionary(grouping: filteredItems, by: \.category)

        return ShoppingListCategory.allCases.compactMap { category in
            guard let items = itemsByCategory[category], !items.isEmpty else {
                return nil
            }

            return ShoppingCategoryGroup(category: category, items: items.sorted())
        }
    }

    private var filteredItems: [ShoppingListItem] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return items
            .filter { item in
                selectedCategory == nil || item.category == selectedCategory
            }
            .filter { item in
                guard !trimmedSearch.isEmpty else {
                    return true
                }

                return item.name.localizedCaseInsensitiveContains(trimmedSearch)
                    || item.category.rawValue.localizedCaseInsensitiveContains(trimmedSearch)
            }
    }

    private var plannedItemCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    private var completedItemCount: Int {
        items.filter(\.isCompleted).count
    }

    private var categoryCounts: [ShoppingListCategory: Int] {
        Dictionary(grouping: items, by: \.category)
            .mapValues(\.count)
    }

    private func toggleCompleted(_ item: ShoppingListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation {
            items[index].isCompleted.toggle()
        }
    }

    private func incrementQuantity(_ item: ShoppingListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation {
            items[index].quantity += 1
        }
    }

    private func decrementQuantity(_ item: ShoppingListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation {
            items[index].quantity = max(1, items[index].quantity - 1)
        }
    }

    private func addDraftItem() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        withAnimation {
            items.append(
                ShoppingListItem(
                    name: name,
                    quantity: draftQuantity,
                    category: draftCategory,
                    isCompleted: false
                )
            )
        }

        resetDraft()
        isShowingAddItem = false
    }

    private func resetDraft() {
        draftName = ""
        draftQuantity = 1
        draftCategory = .produce
    }
}

private struct ShoppingListSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(AppColors.mutedText)
                .frame(width: 24)

            TextField("Filter by item or category", text: $searchText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.mutedText)
                }
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ShoppingCategoryFilterBar: View {
    @Binding var selectedCategory: ShoppingListCategory?
    let counts: [ShoppingListCategory: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                filterButton(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    count: counts.values.reduce(0, +),
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }

                ForEach(ShoppingListCategory.allCases) { category in
                    filterButton(
                        title: category.rawValue,
                        systemImage: category.systemImage,
                        count: counts[category] ?? 0,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func filterButton(
        title: String,
        systemImage: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : AppColors.mutedText)
            }
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 36)
            .foregroundStyle(isSelected ? .white : AppColors.accent)
            .background(isSelected ? AppColors.accent : AppColors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ShoppingCategorySection: View {
    let group: ShoppingCategoryGroup
    let onToggleCompleted: (ShoppingListItem) -> Void
    let onIncrementQuantity: (ShoppingListItem) -> Void
    let onDecrementQuantity: (ShoppingListItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: group.category.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(group.category.tone.foregroundColor)
                    .frame(width: 30, height: 30)
                    .background(group.category.tone.backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.badge, style: .continuous))

                Text(group.category.rawValue)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(group.items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)

            Divider()
                .padding(.leading, AppSpacing.large)

            ForEach(group.items) { item in
                ShoppingItemRow(
                    item: item,
                    onToggleCompleted: { onToggleCompleted(item) },
                    onIncrementQuantity: { onIncrementQuantity(item) },
                    onDecrementQuantity: { onDecrementQuantity(item) }
                )

                if item.id != group.items.last?.id {
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
        .background(AppColors.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.panel, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ShoppingItemRow: View {
    let item: ShoppingListItem
    let onToggleCompleted: () -> Void
    let onIncrementQuantity: () -> Void
    let onDecrementQuantity: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Button(action: onToggleCompleted) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(item.isCompleted ? AppColors.success : AppColors.mutedText)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark \(item.name) needed" : "Mark \(item.name) picked up")

            Text(item.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.isCompleted ? AppColors.mutedText : .primary)
                .strikethrough(item.isCompleted, color: AppColors.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: AppSpacing.small)

            QuantityStepper(
                quantity: item.quantity,
                isDisabled: item.isCompleted,
                onDecrement: onDecrementQuantity,
                onIncrement: onIncrementQuantity
            )
        }
        .padding(AppSpacing.medium)
        .opacity(item.isCompleted ? 0.72 : 1)
    }
}

private struct QuantityStepper: View {
    let quantity: Int
    let isDisabled: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || quantity <= 1)
            .accessibilityLabel("Decrease quantity")

            Text("\(quantity)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isDisabled ? AppColors.mutedText : .primary)
                .frame(minWidth: 26)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel("Increase quantity")
        }
        .padding(.horizontal, AppSpacing.xSmall)
        .frame(height: 36)
        .foregroundStyle(isDisabled ? AppColors.mutedText : AppColors.accent)
        .background(isDisabled ? Color(uiColor: .tertiarySystemFill) : AppColors.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppCornerRadius.control, style: .continuous)
                .stroke(AppColors.panelBorder, lineWidth: 1)
        }
    }
}

private struct ShoppingCategoryGroup: Identifiable {
    let category: ShoppingListCategory
    let items: [ShoppingListItem]

    var id: ShoppingListCategory { category }
}

private struct ShoppingListItem: Identifiable, Comparable {
    let id = UUID()
    var name: String
    var quantity: Int
    var category: ShoppingListCategory
    var isCompleted: Bool

    static func < (lhs: ShoppingListItem, rhs: ShoppingListItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted && rhs.isCompleted
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    static let samples: [ShoppingListItem] = [
        ShoppingListItem(name: "Bananas", quantity: 6, category: .produce, isCompleted: false),
        ShoppingListItem(name: "Avocados", quantity: 4, category: .produce, isCompleted: false),
        ShoppingListItem(name: "Strawberries", quantity: 2, category: .produce, isCompleted: false),
        ShoppingListItem(name: "Whole milk", quantity: 1, category: .dairy, isCompleted: false),
        ShoppingListItem(name: "Greek yogurt", quantity: 4, category: .dairy, isCompleted: false),
        ShoppingListItem(name: "Oatmeal", quantity: 1, category: .pantry, isCompleted: false),
        ShoppingListItem(name: "Pasta", quantity: 2, category: .pantry, isCompleted: false),
        ShoppingListItem(name: "Coffee", quantity: 1, category: .pantry, isCompleted: false),
        ShoppingListItem(name: "Paper towels", quantity: 1, category: .household, isCompleted: true)
    ]
}

private enum ShoppingListCategory: String, CaseIterable, Identifiable {
    case produce = "Produce"
    case dairy = "Dairy"
    case pantry = "Pantry"
    case household = "Home"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .produce:
            return "carrot"
        case .dairy:
            return "drop"
        case .pantry:
            return "cabinet"
        case .household:
            return "house"
        }
    }

    var tone: StatusBadgeTone {
        switch self {
        case .produce:
            return .success
        case .dairy:
            return .accent
        case .pantry, .household:
            return .neutral
        }
    }
}

#Preview {
    NavigationStack {
        ShoppingListMockupView()
    }
}

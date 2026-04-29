import SwiftUI

@MainActor
struct ShoppingListView: View {
    @Environment(HomeManager.self) private var homeManager
    @Environment(ShoppingViewModel.self) private var sharedViewModel
    @Environment(HazelViewModel.self) private var hazelViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingAddItemPage = false
    @State private var showingNextShopSheet = false
    @Bindable private var tripCompletionBridge = ShoppingTripCompletionBridge.shared
    @State private var collapsedCategories: Set<String> = []
    @State private var hasAppeared = false
    @State private var isClearingCompleted = false
    @State private var isSavingNextShopDate = false
    private let previewViewModel: ShoppingViewModel?
    private let homeService = HomeService()

    init(viewModel: ShoppingViewModel? = nil) {
        previewViewModel = viewModel
    }

    private var viewModel: ShoppingViewModel { previewViewModel ?? sharedViewModel }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                content
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.roostShoppingTint.opacity(0.72), Color.roostShoppingTint.opacity(0.28)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
                .ignoresSafeArea(edges: .top)
        }
        .background(Color.roostBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showingAddItemPage) {
            AddShoppingItemSheet(
                suggestedCategories: suggestedCategories,
                suggestedQuantities: suggestedQuantities
            ) { name, quantity, category in
                guard let homeId = homeManager.homeId,
                      let userId = homeManager.currentUserId else {
                    viewModel.errorMessage = "Home not loaded yet. Try again in a moment."
                    return
                }
                await viewModel.addItem(
                    name: name,
                    quantity: quantity,
                    category: category,
                    homeId: homeId,
                    userId: userId,
                    hazelEnabled: hazelViewModel.shoppingEnabled
                )
            }
        }
        .sheet(isPresented: $showingNextShopSheet) {
            NextShopDateSheet(
                selectedDate: homeManager.home?.nextShopDateParsed ?? defaultNextShopDate,
                isSaving: isSavingNextShopDate
            ) { date in
                await saveNextShopDate(date)
            }
        }
        .sheet(isPresented: $tripCompletionBridge.pendingCompletion) {
            ShoppingTripCompletionSheet(
                merchant: tripCompletionBridge.suggestedMerchant,
                onDismiss: { tripCompletionBridge.clear() }
            )
            .presentationDetents([.medium])
        }
        .conditionalRefreshable(!showingNextShopSheet) {
            let homeId = await MainActor.run { homeManager.homeId }
            guard let homeId else { return }
            await viewModel.loadItems(homeId: homeId)
        }
        .task {
            guard !reduceMotion else {
                hasAppeared = true
                return
            }
            withAnimation(.roostSmooth) {
                hasAppeared = true
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.roostCaption)
                    .foregroundStyle(Color.roostCard)
                    .padding(Spacing.md)
                    .background(Color.roostDestructive, in: Capsule())
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, DesignSystem.Size.toastBottomOffset)
                    .onTapGesture { viewModel.errorMessage = nil }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
                .padding(.top, 16)
                .shoppingEntrance(at: 0, hasAppeared: hasAppeared, reduceMotion: reduceMotion)

            shoppingHero
                .padding(.top, 22)
                .shoppingEntrance(at: 1, hasAppeared: hasAppeared, reduceMotion: reduceMotion)

            quickActionRail
                .padding(.top, 12)
                .shoppingEntrance(at: 2, hasAppeared: hasAppeared, reduceMotion: reduceMotion)

            // Start / end a shopping-trip Live Activity. Shows on the lock
            // screen + Dynamic Island so items can be checked off hands-free.
            HStack {
                ShoppingTripStartButton()
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .shoppingEntrance(at: 2, hasAppeared: hasAppeared, reduceMotion: reduceMotion)

            if viewModel.isLoading && viewModel.items.isEmpty {
                loadingState
                    .padding(.top, 24)
                    .shoppingEntrance(at: 3, hasAppeared: hasAppeared, reduceMotion: reduceMotion)
            } else if viewModel.items.isEmpty {
                emptyState
                    .padding(.top, 24)
                    .shoppingEntrance(at: 3, hasAppeared: hasAppeared, reduceMotion: reduceMotion)
            } else {
                itemsBoard
                    .padding(.top, 24)

                if !checkedItems.isEmpty {
                    completedDock
                        .padding(.top, 14)
                        .shoppingEntrance(at: 3 + categoryGroups.count, hasAppeared: hasAppeared, reduceMotion: reduceMotion)
                }
            }
        }
        .padding(.horizontal, shoppingPageInset)
        .padding(.bottom, DesignSystem.Spacing.screenBottom + DesignSystem.Spacing.tabContentBottomInset + 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shopping")
                    .font(.roostLargeGreeting)
                    .foregroundStyle(Color.roostForeground)

                Text(headerSubtitle)
                    .font(.roostBody)
                    .foregroundStyle(Color.roostMutedForeground)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Hero Card

    private var shoppingHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SHOPPING LIST")
                        .font(.roostMeta)
                        .foregroundStyle(Color.roostShoppingTint)
                        .tracking(1.0)

                    Text(heroTitle)
                        .font(.roostHero)
                        .foregroundStyle(Color.roostForeground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                }

                Spacer(minLength: 0)

                shoppingProgressDial
                    .frame(width: 76, height: 76)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nextShopTitle)
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostForeground)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let nextShopDate = homeManager.home?.nextShopDateParsed {
                        Text(nextShopChipTitle(for: nextShopDate))
                            .font(.roostMeta)
                            .foregroundStyle(nextShopAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(nextShopAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.roostMuted)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.roostShoppingTint)
                                .frame(width: geo.size.width * completionProgress)
                                .animation(DesignSystem.Motion.progressFill, value: completionProgress)
                        }
                }
                .frame(height: 7)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                    .fill(Color.roostCard)

                Circle()
                    .fill(Color.roostShoppingTint.opacity(0.11))
                    .frame(width: 124, height: 124)
                    .blur(radius: 32)
                    .offset(x: 40, y: -52)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                .stroke(Color.roostHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.045), radius: 12, x: 0, y: 5)
    }

    private var shoppingProgressDial: some View {
        ZStack {
            Circle()
                .stroke(Color.roostMuted, lineWidth: 8)

            Circle()
                .trim(from: 0, to: completionProgress)
                .stroke(
                    Color.roostShoppingTint,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(DesignSystem.Motion.progressFill, value: completionProgress)

            VStack(spacing: 1) {
                Text("\(uncheckedCount)")
                    .font(.roostCardTitle)
                    .foregroundStyle(Color.roostForeground)
                Text("left")
                    .font(.roostMeta)
                    .foregroundStyle(Color.roostMutedForeground)
            }
        }
    }

    // MARK: - Quick Action Rail

    private var quickActionRail: some View {
        HStack(spacing: 10) {
            shoppingActionTile(
                title: "Add",
                detail: "New item",
                icon: "plus",
                tint: Color.roostShoppingTint,
                isProminent: true
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
                showingAddItemPage = true
            }

            shoppingActionTile(
                title: "Next Shop",
                detail: nextShopTileDetail,
                icon: "calendar",
                tint: nextShopTileAccent
            ) {
                UISelectionFeedbackGenerator().selectionChanged()
                showingNextShopSheet = true
            }

            shoppingActionTile(
                title: "Clear",
                detail: "\(checkedItems.count) done",
                icon: "checkmark",
                tint: checkedItems.isEmpty ? .roostMutedForeground : .roostSuccess
            ) {
                guard !checkedItems.isEmpty else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                Task { await clearCompleted() }
            }
            .disabled(checkedItems.isEmpty || isClearingCompleted)
        }
    }

    private func shoppingActionTile(
        title: String,
        detail: String,
        icon: String,
        tint: Color,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(isProminent ? 0.13 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostForeground)
                        .lineLimit(1)

                    Text(detail)
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.roostCard, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .stroke(isProminent ? tint.opacity(0.20) : Color.roostHairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        }
        .buttonStyle(ShoppingPressStyle(reduceMotion: reduceMotion))
    }

    // MARK: - Items Board

    private var itemsBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if uncheckedItems.isEmpty {
                allClearState
            } else {
                ForEach(Array(categoryGroups.enumerated()), id: \.element.category) { index, group in
                    categoryGroupSection(group, index: index)
                }
            }
        }
    }

    private func categoryGroupSection(_ group: CategoryGroup, index: Int) -> some View {
        let isCollapsed = collapsedCategories.contains(group.category)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.roostEaseOut) {
                    toggleCategory(group.category)
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.roostShoppingTint.opacity(0.11))
                        Image(systemName: categoryIcon(for: group.category))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.roostShoppingTint)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.category)
                            .font(.roostCardTitle)
                            .foregroundStyle(Color.roostForeground)

                        Text("\(group.items.count) \(group.items.count == 1 ? "item" : "items")")
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostMutedForeground)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        Text("\(group.items.count)")
                            .font(.roostLabel)
                            .foregroundStyle(Color.roostShoppingTint)
                            .frame(width: 30, height: 30)
                            .background(Color.roostShoppingTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.roostMutedForeground)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
            }
            .buttonStyle(ShoppingPressStyle(reduceMotion: reduceMotion))

            if !isCollapsed {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        ShoppingItemRow(item: item, addedByName: memberName(for: item.addedBy)) {
                            guard let homeId = homeManager.homeId,
                                  let userId = homeManager.currentUserId else { return }
                            Task { await viewModel.toggleItem(item, homeId: homeId, userId: userId) }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                guard let homeId = homeManager.homeId,
                                      let userId = homeManager.currentUserId else { return }
                                Task { await viewModel.deleteItem(item, homeId: homeId, userId: userId) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.roostCard.opacity(0.9), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .stroke(Color.roostHairline, lineWidth: 1)
        )
        .shoppingEntrance(at: index + 3, hasAppeared: hasAppeared, reduceMotion: reduceMotion)
    }

    // MARK: - Completed Dock

    private var completedDock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.roostSuccess)
                    .frame(width: 30, height: 30)
                    .background(Color.roostSuccess.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(uncheckedItems.isEmpty ? "List complete" : "\(checkedItems.count) in basket")
                        .font(.roostCardTitle)
                        .foregroundStyle(Color.roostForeground)

                    Text(uncheckedItems.isEmpty ? "Everything's in the basket!" : "Clear when you're done shopping.")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                }

                Spacer(minLength: 0)
            }

            Button {
                Task { await clearCompleted() }
            } label: {
                Text(isClearingCompleted ? "Clearing..." : "Clear basket items")
                    .font(.roostLabel)
                    .foregroundStyle(Color.roostSuccess)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.roostSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(ShoppingPressStyle(reduceMotion: reduceMotion))
            .disabled(isClearingCompleted)
        }
        .padding(15)
        .background(Color.roostSurface, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .stroke(Color.roostHairline, lineWidth: 1)
        )
    }

    // MARK: - States

    private var allClearState: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("All in the basket")
                    .font(.roostCardTitle)
                    .foregroundStyle(Color.roostForeground)

                Text("Everything's been picked up.")
                    .font(.roostCaption)
                    .foregroundStyle(Color.roostMutedForeground)
            }

            Spacer(minLength: 0)

            Image(systemName: "cart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.roostSuccess)
                .frame(width: 40, height: 40)
                .background(Color.roostSuccess.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color.roostSurface, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .stroke(Color.roostHairline, lineWidth: 1)
        )
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(0..<4, id: \.self) { _ in
                LoadingSkeletonView()
                    .frame(height: 92)
            }
        }
    }

    private var emptyState: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("List is empty")
                    .font(.roostCardTitle)
                    .foregroundStyle(Color.roostForeground)

                Text("Tap Add to put the first item on the list.")
                    .font(.roostCaption)
                    .foregroundStyle(Color.roostMutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "cart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.roostShoppingTint)
                .frame(width: 40, height: 40)
                .background(Color.roostShoppingTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color.roostSurface, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                .stroke(Color.roostHairline, lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private var categoryGroups: [CategoryGroup] {
        let grouped = Dictionary(grouping: uncheckedItems) { item in
            (item.category?.isEmpty == false) ? item.category! : "Other"
        }
        return grouped
            .sorted { $0.key == "Other" ? true : ($1.key == "Other" ? false : $0.key < $1.key) }
            .map { CategoryGroup(category: $0.key, items: $0.value.sorted { $0.createdAt < $1.createdAt }) }
    }

    private var uncheckedItems: [ShoppingItem] {
        viewModel.items.filter { !$0.checked }
    }

    private var checkedItems: [ShoppingItem] {
        viewModel.items.filter(\.checked)
    }

    private var uncheckedCount: Int { uncheckedItems.count }

    private var completionProgress: CGFloat {
        guard !viewModel.items.isEmpty else { return 0 }
        return CGFloat(checkedItems.count) / CGFloat(viewModel.items.count)
    }

    private var heroTitle: String {
        if viewModel.items.isEmpty { return "No items" }
        if uncheckedCount == 0 { return "All clear" }
        if uncheckedCount == 1 { return "1 item" }
        return "\(uncheckedCount) items"
    }

    private var headerSubtitle: String {
        if viewModel.items.isEmpty { return "Add items to get started" }
        if uncheckedCount == 0 { return "All picked up · Shared live" }
        return "\(uncheckedCount) to buy · Shared live"
    }

    private var nextShopTitle: String {
        guard let nextShopDate = homeManager.home?.nextShopDateParsed else {
            return "Set your next shop date"
        }
        return nextShopDate.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var nextShopTileDetail: String {
        guard let nextShopDate = homeManager.home?.nextShopDateParsed else { return "Not set" }
        return nextShopChipTitle(for: nextShopDate)
    }

    private var nextShopTileAccent: Color {
        guard let nextShopDate = homeManager.home?.nextShopDateParsed else { return .roostMutedForeground }
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: nextShopDate)).day ?? 0
        if days < 0 { return .roostDestructive }
        if days <= 3 { return .roostWarning }
        return Color.roostShoppingTint
    }

    private var nextShopAccent: Color { nextShopTileAccent }

    // MARK: - Helpers

    private func nextShopChipTitle(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return "Overdue"
        case 0: return "Today!"
        case 1: return "Tomorrow"
        default: return "In \(days) days"
        }
    }

    private func categoryIcon(for category: String) -> String {
        switch category.lowercased() {
        case let c where c.contains("produce") || c.contains("fruit") || c.contains("veg"): return "leaf"
        case let c where c.contains("dairy"): return "drop"
        case let c where c.contains("bak"): return "flame"
        case let c where c.contains("meat") || c.contains("fish"): return "fish"
        case let c where c.contains("frozen"): return "snowflake"
        case let c where c.contains("drink") || c.contains("beverage"): return "cup.and.saucer"
        case let c where c.contains("snack"): return "popcorn"
        case let c where c.contains("household") || c.contains("cleaning"): return "house"
        case let c where c.contains("personal") || c.contains("care") || c.contains("beauty"): return "heart"
        case let c where c.contains("pantry") || c.contains("tinned") || c.contains("pasta"): return "cabinet"
        default: return "cart"
        }
    }

    private var defaultNextShopDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    }

    private func saveNextShopDate(_ date: Date) async {
        guard let homeId = homeManager.homeId, !isSavingNextShopDate else { return }
        isSavingNextShopDate = true
        defer { isSavingNextShopDate = false }
        do {
            try await homeService.updateNextShopDate(homeId: homeId, date: date)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if homeManager.home != nil {
                homeManager.home?.nextShopDate = formatter.string(from: date)
            }
            showingNextShopSheet = false
        } catch {
            viewModel.errorMessage = "Couldn't update the next shop date."
        }
    }

    private func clearCompleted() async {
        guard let homeId = homeManager.homeId,
              let userId = homeManager.currentUserId else { return }
        isClearingCompleted = true
        let completed = checkedItems
        for item in completed {
            await viewModel.deleteItem(item, homeId: homeId, userId: userId)
        }
        isClearingCompleted = false
    }

    private func toggleCategory(_ category: String) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
    }

    private func memberName(for userId: UUID?) -> String? {
        guard let userId else { return nil }
        if userId == homeManager.currentUserId { return homeManager.currentMember?.displayName ?? "You" }
        if userId == homeManager.partner?.userID { return homeManager.partner?.displayName }
        return homeManager.members.first(where: { $0.userID == userId })?.displayName
    }

    private var suggestedCategories: [String] {
        let fromItems = Set(
            viewModel.items
                .compactMap(\.category)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let base = Set(Self.baseCategories)
        return Self.baseCategories + fromItems.subtracting(base).sorted()
    }

    private var suggestedQuantities: [String] {
        Array(Set(
            viewModel.items
                .compactMap(\.quantity)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )).sorted()
    }

    private static let baseCategories: [String] = [
        "Produce", "Dairy", "Bakery", "Meat & Fish",
        "Frozen", "Drinks", "Snacks", "Household", "Personal Care"
    ]
}

// MARK: - Category Group Model

private let shoppingPageInset: CGFloat = 12

private struct CategoryGroup {
    let category: String
    let items: [ShoppingItem]
}

// MARK: - Next Shop Date Sheet

private struct NextShopDateSheet: View {
    let selectedDate: Date
    let isSaving: Bool
    let onPickDate: (Date) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftDate: Date
    @State private var appeared = false

    private let quickPicks: [(label: String, days: Int)] = [
        ("Today", 0), ("Tomorrow", 1), ("In 3 days", 3), ("Next week", 7)
    ]

    init(selectedDate: Date, isSaving: Bool, onPickDate: @escaping (Date) async -> Void) {
        self.selectedDate = selectedDate
        self.isSaving = isSaving
        self.onPickDate = onPickDate
        _draftDate = State(initialValue: selectedDate)
    }

    var body: some View {
        VStack(spacing: 0) {

            // Handle
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.roostMuted)
                .frame(width: 36, height: 4)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
                .modifier(SheetSectionEntrance(index: 0, appeared: appeared, reduceMotion: reduceMotion))

            // Header row
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.roostShoppingTint.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "cart.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.roostShoppingTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT SHOP")
                        .font(.roostMeta)
                        .foregroundStyle(Color.roostShoppingTint)
                        .tracking(1.2)
                    Text(formattedDraftDate)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.roostForeground)
                        .contentTransition(.numericText())
                        .animation(DesignSystem.Motion.buttonRelease, value: draftDate)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.roostMutedForeground)
                        .frame(width: 30, height: 30)
                        .background(Color.roostMuted.opacity(0.6), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.lg)
            .modifier(SheetSectionEntrance(index: 1, appeared: appeared, reduceMotion: reduceMotion))

            // Quick-pick chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(quickPicks, id: \.days) { pick in
                        let target = Calendar.current.date(byAdding: .day, value: pick.days, to: Calendar.current.startOfDay(for: .now)) ?? .now
                        let isSelected = Calendar.current.isDate(draftDate, inSameDayAs: target)

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(DesignSystem.Motion.buttonRelease) { draftDate = target }
                        } label: {
                            Text(pick.label)
                                .font(.roostLabel)
                                .foregroundStyle(isSelected ? Color.roostCard : Color.roostMutedForeground)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected
                                        ? Color.roostShoppingTint
                                        : Color.roostMuted.opacity(0.55),
                                    in: Capsule()
                                )
                                .animation(DesignSystem.Motion.buttonRelease, value: isSelected)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .padding(.top, Spacing.lg)

            // Calendar picker inside a card
            VStack(spacing: 0) {
                DatePicker(
                    "Next shop date",
                    selection: $draftDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.roostShoppingTint)
                .disabled(isSaving)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(Color.roostCard, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .stroke(Color.roostHairline, lineWidth: 1)
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .modifier(SheetSectionEntrance(index: 2, appeared: appeared, reduceMotion: reduceMotion))

            Spacer(minLength: Spacing.md)

            // Confirm button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await onPickDate(draftDate) }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.roostCard)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isSaving ? "Saving…" : "Set date")
                        .font(.roostLabel)
                }
                .foregroundStyle(Color.roostCard)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    isSaving
                        ? Color.roostShoppingTint.opacity(0.6)
                        : Color.roostShoppingTint,
                    in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
            .modifier(SheetSectionEntrance(index: 3, appeared: appeared, reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity)
        .background(Color.roostBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(DesignSystem.Radius.xl)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(DesignSystem.Motion.modalTransition.delay(0.05)) {
                appeared = true
            }
        }
    }

    private var formattedDraftDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(draftDate) { return "Today" }
        if cal.isDateInTomorrow(draftDate) { return "Tomorrow" }
        return draftDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

// MARK: - Press Style

private struct ShoppingPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : DesignSystem.Motion.buttonPress, value: configuration.isPressed)
    }
}

// MARK: - Entrance Modifier

private struct ShoppingEntranceModifier: ViewModifier {
    let index: Int
    let hasAppeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: reduceMotion || hasAppeared ? 0 : CGFloat(18 + (index * 4)))
            .animation(reduceMotion ? nil : .roostSmooth.delay(Double(index) * 0.04), value: hasAppeared)
    }
}

private extension View {
    func shoppingEntrance(at index: Int, hasAppeared: Bool, reduceMotion: Bool) -> some View {
        modifier(ShoppingEntranceModifier(index: index, hasAppeared: hasAppeared, reduceMotion: reduceMotion))
    }
}

// MARK: - Sheet Section Entrance

/// Staggered slide-up + fade entrance for NextShopDateSheet content sections.
private struct SheetSectionEntrance: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.97)
            .offset(y: appeared || reduceMotion ? 0 : 22)
            .animation(
                reduceMotion ? nil : DesignSystem.Motion.modalTransition.delay(Double(index) * 0.07),
                value: appeared
            )
    }
}

// MARK: - Preview

#Preview {
    ShoppingListView(viewModel: .previewShopping)
        .environment(HomeManager.previewDashboard())
        .environment(SettingsViewModel())
        .environment(HazelViewModel())
}

private extension ShoppingViewModel {
    static var previewShopping: ShoppingViewModel {
        let homeId = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
        let userId = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
        let partnerId = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()

        return ShoppingViewModel(items: [
            ShoppingItem(id: UUID(), homeID: homeId, name: "Milk", quantity: "2", category: "Dairy", checked: false, addedBy: userId, checkedBy: nil, createdAt: .now.addingTimeInterval(-900), updatedAt: nil),
            ShoppingItem(id: UUID(), homeID: homeId, name: "Bananas", quantity: "6", category: "Produce", checked: false, addedBy: partnerId, checkedBy: nil, createdAt: .now.addingTimeInterval(-3600), updatedAt: nil),
            ShoppingItem(id: UUID(), homeID: homeId, name: "Pasta", quantity: "1", category: "Pantry", checked: true, addedBy: userId, checkedBy: partnerId, createdAt: .now.addingTimeInterval(-7200), updatedAt: nil),
            ShoppingItem(id: UUID(), homeID: homeId, name: "Kitchen roll", quantity: "2", category: "Household", checked: false, addedBy: partnerId, checkedBy: nil, createdAt: .now.addingTimeInterval(-18000), updatedAt: nil)
        ])
    }
}

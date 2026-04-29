//
//  SharedShoppingReader.swift
//  Roost
//
//  Read-path used by the RoostWidgets extension to pull the current
//  shopping list out of the shared SwiftData store. Lives in the shared
//  target so the main app can also use it (e.g. when rebuilding a Live
//  Activity's ContentState).
//
//  Target membership: BOTH `Roost_iOS` and `RoostWidgets`.
//

import Foundation
import SwiftData

enum SharedShoppingReader {
    /// Read unchecked items for the current home, ordered by priority.
    /// Returns an empty array if no home is configured or the store can't
    /// be opened.
    static func fetchItems(limit: Int = 40) -> [ShoppingItemDisplay] {
        guard let homeID = AppGroup.Context.currentHomeID else { return [] }

        do {
            let container = try sharedModelContainer()
            let context = ModelContext(container)

            var descriptor = FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { item in
                    item.homeID == homeID
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = limit

            let rows = try context.fetch(descriptor)

            // Build a member-ID → display name map once so we can annotate
            // each row with the adder's name without N queries.
            let memberNames = memberNameMap(context: context, homeID: homeID)

            let currentUserName = AppGroup.Context.currentUserDisplayName

            return rows.map { row in
                ShoppingItemDisplay(
                    id: row.id,
                    name: row.name,
                    quantity: row.quantity,
                    category: row.category,
                    checked: row.checked,
                    addedAt: row.createdAt,
                    addedByName: nil, // CachedShoppingItem has no addedBy today
                    emoji: nil
                )
            }.sorted { lhs, rhs in
                lhs.priorityScore(currentUserName: currentUserName)
                    > rhs.priorityScore(currentUserName: currentUserName)
            }
        } catch {
            return []
        }
    }

    /// Convenience: split into unchecked / checked buckets for widget layout.
    static func fetchBuckets(limit: Int = 40) -> (unchecked: [ShoppingItemDisplay], checked: [ShoppingItemDisplay]) {
        let all = fetchItems(limit: limit)
        return (
            unchecked: all.filter { !$0.checked },
            checked: all.filter { $0.checked }
        )
    }

    /// Build the ContentState snapshot for the Shopping Trip Live Activity.
    static func currentTripState(previewLimit: Int = 3) -> ShoppingTripAttributes.ContentState {
        let all = fetchItems(limit: 100)
        let unchecked = all.filter { !$0.checked }
        return ShoppingTripAttributes.ContentState(
            totalItems: all.count,
            checkedCount: all.count - unchecked.count,
            previewItems: Array(unchecked.prefix(previewLimit)),
            isCompleted: !all.isEmpty && unchecked.isEmpty
        )
    }

    // MARK: - Internals

    /// A shared `ModelContainer` pointing at the App Group store. Built
    /// lazily and cached to avoid SQLite open costs on every widget refresh.
    private static var cachedContainer: ModelContainer?

    static func sharedModelContainer() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }

        let schema = Schema([
            CachedShoppingItem.self,
            CachedExpense.self,
            CachedChore.self,
            CachedActivityFeedItem.self,
            CachedExpenseSplit.self,
            CachedBudget.self,
            CachedCustomCategory.self,
            CachedSavingsGoal.self,
            CachedCalendarEvent.self,
            CachedPinboardNote.self,
            CachedRoom.self,
            CachedHome.self,
            CachedHomeMember.self,
            CachedHouseholdIncome.self,
            PendingMutation.self,
        ])

        let configuration: ModelConfiguration
        if let url = AppGroup.swiftDataStoreURL {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        let container = try ModelContainer(for: schema, configurations: configuration)
        cachedContainer = container
        return container
    }

    private static func memberNameMap(context: ModelContext, homeID: UUID) -> [UUID: String] {
        let descriptor = FetchDescriptor<CachedHomeMember>(
            predicate: #Predicate { member in
                member.homeID == homeID
            }
        )
        guard let members = try? context.fetch(descriptor) else { return [:] }
        var map: [UUID: String] = [:]
        for m in members {
            map[m.userID] = m.displayName
        }
        return map
    }
}

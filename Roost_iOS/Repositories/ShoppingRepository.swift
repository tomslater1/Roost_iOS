import Foundation
import SwiftData

// MARK: - ShoppingRepository
//
// Cache-first reads for the shopping list. Writes go through
// `OfflineAwareWrite.enqueue` — see `ShoppingMutationHandler` for the
// replay side.
//
// Dirty-row policy matches `ExpenseRepository`: a `CachedShoppingItem`
// whose `isDirty == true` is never overwritten by a server refresh until
// its pending mutation has drained. Server-side deletes are ignored on
// dirty local rows (a common race: "I checked this offline, my partner
// also deleted it" → the check is preserved locally until drain, then
// reconciled normally on the next refresh).

@MainActor
struct ShoppingRepository: Repository {
    typealias Model = ShoppingItem

    private let container: ModelContainer
    private let service: ShoppingService

    init(container: ModelContainer? = nil, service: ShoppingService = ShoppingService()) {
        self.container = container ?? LocalDataManager.shared.container
        self.service = service
    }

    // MARK: Cache reads

    func loadCached(homeID: UUID) throws -> [ShoppingItem] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedShoppingItem>(
            predicate: #Predicate { $0.homeID == homeID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { row in
            ShoppingItem(
                id: row.id,
                homeID: row.homeID,
                name: row.name,
                quantity: row.quantity,
                category: row.category,
                checked: row.checked,
                addedBy: nil,
                checkedBy: nil,
                createdAt: row.createdAt,
                updatedAt: row.lastSyncedAt
            )
        }
    }

    // MARK: Refresh

    func refresh(homeID: UUID) async throws {
        let fresh = try await service.fetchItems(for: homeID)
        try upsertLocal(fresh, homeID: homeID)
    }

    // MARK: Cache merge (server → cache, dirty-preserving)

    func upsertLocal(_ items: [ShoppingItem], homeID: UUID) throws {
        let context = container.mainContext
        let existing = try context.fetch(
            FetchDescriptor<CachedShoppingItem>(predicate: #Predicate { $0.homeID == homeID })
        )
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(items.map(\.id))
        let now = Date()

        // Drop stale non-dirty rows (they're gone server-side).
        for cached in existing where !incomingIDs.contains(cached.id) && !cached.isDirty {
            context.delete(cached)
        }

        for item in items {
            if let row = existingByID[item.id] {
                if row.isDirty { continue } // local write wins until drain
                row.homeID = item.homeID
                row.name = item.name
                row.quantity = item.quantity
                row.category = item.category
                row.checked = item.checked
                row.createdAt = item.createdAt
                row.lastSyncedAt = now
                row.pendingOperation = nil
            } else {
                let fresh = CachedShoppingItem(from: item)
                fresh.lastSyncedAt = now
                context.insert(fresh)
            }
        }

        try context.save()
    }

    // MARK: Optimistic cache writes

    func applyOptimisticUpsert(_ item: ShoppingItem, pendingOperation: String) throws {
        let context = container.mainContext
        let itemID = item.id
        let existing = try context.fetch(
            FetchDescriptor<CachedShoppingItem>(predicate: #Predicate { $0.id == itemID })
        ).first

        if let row = existing {
            row.homeID = item.homeID
            row.name = item.name
            row.quantity = item.quantity
            row.category = item.category
            row.checked = item.checked
            row.isDirty = true
            row.pendingOperation = pendingOperation
        } else {
            let fresh = CachedShoppingItem(from: item)
            fresh.isDirty = true
            fresh.pendingOperation = pendingOperation
            context.insert(fresh)
        }
        try context.save()
    }

    func applyOptimisticDelete(itemID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedShoppingItem>(predicate: #Predicate { $0.id == itemID })
        ).first {
            context.delete(row)
        }
        try context.save()
    }

    // MARK: Drain hooks

    func clearDirty(itemID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedShoppingItem>(predicate: #Predicate { $0.id == itemID })
        ).first {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    // MARK: Repository conformance fallback

    func upsertLocal(_ items: [ShoppingItem]) throws {
        guard let homeID = items.first?.homeID else { return }
        try upsertLocal(items, homeID: homeID)
    }
}

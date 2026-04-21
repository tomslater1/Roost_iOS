import Foundation
import SwiftData

// MARK: - BudgetRepository
//
// Cache-first reads for the Budgets domain. Wraps two tables:
//   - `CachedBudget` (home_id, category, month → amount)
//   - `CachedCustomCategory` (user-defined category definitions for a home)
//
// Budgets use a composite natural key `(homeID, category, month)` on the
// server (`onConflict: "home_id,category,month"`), so offline creates don't
// need the InsertExpense-style client UUID dance — we just let the client
// generate a UUID when we insert locally and the server-issued row lands on
// top of it by natural key at the next refresh.
//
// Dirty-row policy (same as Expenses):
//   - A dirty `CachedBudget` is preserved across `refresh()`.
//   - Non-dirty rows whose server counterpart disappeared are deleted.
//   - Handler clears the dirty flag after a successful replay, then refreshes.

@MainActor
struct BudgetRepository: Repository {
    typealias Model = Budget

    private let container: ModelContainer
    private let service: BudgetService

    init(container: ModelContainer? = nil, service: BudgetService = BudgetService()) {
        self.container = container ?? LocalDataManager.shared.container
        self.service = service
    }

    // MARK: Cache reads

    func loadCached(homeID: UUID) throws -> [Budget] {
        let context = container.mainContext
        let rows = try context.fetch(
            FetchDescriptor<CachedBudget>(predicate: #Predicate { $0.homeID == homeID })
        )
        return rows.map { row in
            Budget(
                id: row.id,
                homeID: row.homeID,
                category: row.category,
                amount: row.amount,
                month: row.month
            )
        }
    }

    func loadCachedCustomCategories(homeID: UUID) throws -> [CustomCategory] {
        let context = container.mainContext
        let rows = try context.fetch(
            FetchDescriptor<CachedCustomCategory>(
                predicate: #Predicate { $0.homeID == homeID },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
        )
        return rows.map { row in
            CustomCategory(
                id: row.id,
                homeID: row.homeID,
                name: row.name,
                emoji: row.emoji,
                color: row.colour,
                createdAt: row.createdAt
            )
        }
    }

    // MARK: Refresh

    func refresh(homeID: UUID) async throws {
        let fresh = try await service.fetchBudgets(for: homeID)
        try upsertLocal(fresh, homeID: homeID)
    }

    func refreshCustomCategories(homeID: UUID) async throws {
        let fresh = try await service.fetchCustomCategories(for: homeID)
        try upsertLocalCustomCategories(fresh, homeID: homeID)
    }

    // MARK: Cache merge (server → cache, dirty-preserving)

    func upsertLocal(_ items: [Budget], homeID: UUID) throws {
        let context = container.mainContext
        let existing = try context.fetch(
            FetchDescriptor<CachedBudget>(predicate: #Predicate { $0.homeID == homeID })
        )
        let incomingIDs = Set(items.map(\.id))
        let now = Date()

        // Drop stale non-dirty rows.
        for cached in existing where !incomingIDs.contains(cached.id) && !cached.isDirty {
            context.delete(cached)
        }

        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for item in items {
            if let row = existingByID[item.id] {
                if row.isDirty { continue }
                row.homeID = item.homeID
                row.category = item.category
                row.amount = item.amount
                row.month = item.month
                row.lastSyncedAt = now
                row.pendingOperation = nil
            } else {
                // Dedupe against a dirty local row with the same natural key
                // (home, category, month) — that local row represents the
                // optimistic create the server has just confirmed.
                if let dirtyMatch = existing.first(where: {
                    $0.isDirty &&
                    $0.category.caseInsensitiveCompare(item.category) == .orderedSame &&
                    Calendar.current.isDate($0.month, equalTo: item.month, toGranularity: .month)
                }) {
                    dirtyMatch.id = item.id
                    dirtyMatch.amount = item.amount
                    dirtyMatch.lastSyncedAt = now
                    dirtyMatch.isDirty = false
                    dirtyMatch.pendingOperation = nil
                } else {
                    let fresh = CachedBudget(from: item)
                    fresh.lastSyncedAt = now
                    context.insert(fresh)
                }
            }
        }

        try context.save()
    }

    func upsertLocalCustomCategories(_ items: [CustomCategory], homeID: UUID) throws {
        let context = container.mainContext
        let existing = try context.fetch(
            FetchDescriptor<CachedCustomCategory>(predicate: #Predicate { $0.homeID == homeID })
        )
        let incomingIDs = Set(items.map(\.id))
        let now = Date()

        for cached in existing where !incomingIDs.contains(cached.id) && !cached.isDirty {
            context.delete(cached)
        }

        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for item in items {
            if let row = existingByID[item.id] {
                if row.isDirty { continue }
                row.name = item.name
                row.emoji = item.emoji
                row.colour = item.color
                row.lastSyncedAt = now
                row.pendingOperation = nil
            } else {
                if let dirtyMatch = existing.first(where: {
                    $0.isDirty && $0.name.caseInsensitiveCompare(item.name) == .orderedSame
                }) {
                    dirtyMatch.id = item.id
                    dirtyMatch.emoji = item.emoji
                    dirtyMatch.colour = item.color
                    dirtyMatch.createdAt = item.createdAt
                    dirtyMatch.lastSyncedAt = now
                    dirtyMatch.isDirty = false
                    dirtyMatch.pendingOperation = nil
                } else {
                    let fresh = CachedCustomCategory(from: item)
                    fresh.lastSyncedAt = now
                    context.insert(fresh)
                }
            }
        }

        try context.save()
    }

    // MARK: - Optimistic cache writes

    /// Applies an optimistic upsert for a budget identified by natural key
    /// `(homeID, category, month)`. Returns the local row's UUID so the VM
    /// can emit it in UI. If a row with the same natural key already exists
    /// locally we update that row (preserving its ID) rather than creating
    /// a sibling — this mirrors server behaviour under the composite unique
    /// constraint.
    @discardableResult
    func applyOptimisticBudgetUpsert(
        homeID: UUID,
        category: String,
        amount: Decimal,
        month: Date,
        pendingOperation: String = "upsert"
    ) throws -> Budget {
        let context = container.mainContext
        let rows = try context.fetch(
            FetchDescriptor<CachedBudget>(predicate: #Predicate { $0.homeID == homeID })
        )
        let match = rows.first { row in
            row.category.caseInsensitiveCompare(category) == .orderedSame &&
            Calendar.current.isDate(row.month, equalTo: month, toGranularity: .month)
        }

        let row: CachedBudget
        if let existing = match {
            existing.amount = amount
            existing.category = category
            existing.month = month
            existing.isDirty = true
            existing.pendingOperation = pendingOperation
            row = existing
        } else {
            let fresh = CachedBudget(
                id: UUID(),
                homeID: homeID,
                category: category,
                amount: amount,
                month: month
            )
            fresh.isDirty = true
            fresh.pendingOperation = pendingOperation
            context.insert(fresh)
            row = fresh
        }

        try context.save()
        return Budget(id: row.id, homeID: row.homeID, category: row.category, amount: row.amount, month: row.month)
    }

    func applyOptimisticBudgetDelete(budgetID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedBudget>(predicate: #Predicate { $0.id == budgetID })
        ).first {
            context.delete(row)
        }
        try context.save()
    }

    @discardableResult
    func applyOptimisticCategoryInsert(
        homeID: UUID,
        name: String,
        emoji: String,
        color: String?,
        pendingOperation: String = "create"
    ) throws -> CustomCategory {
        let context = container.mainContext
        let fresh = CachedCustomCategory(
            id: UUID(),
            homeID: homeID,
            name: name,
            emoji: emoji,
            colour: color,
            createdAt: Date()
        )
        fresh.isDirty = true
        fresh.pendingOperation = pendingOperation
        context.insert(fresh)
        try context.save()
        return CustomCategory(
            id: fresh.id,
            homeID: fresh.homeID,
            name: fresh.name,
            emoji: fresh.emoji,
            color: fresh.colour,
            createdAt: fresh.createdAt
        )
    }

    func applyOptimisticCategoryDelete(categoryID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedCustomCategory>(predicate: #Predicate { $0.id == categoryID })
        ).first {
            context.delete(row)
        }
        try context.save()
    }

    // MARK: - Drain hooks

    func clearBudgetDirty(budgetID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedBudget>(predicate: #Predicate { $0.id == budgetID })
        ).first {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    /// Clears any dirty marker on a budget that matches the given natural key.
    /// Used after a successful upsert replay when the server may have issued
    /// a different UUID than the one we minted locally.
    func clearBudgetDirty(homeID: UUID, category: String, month: Date) throws {
        let context = container.mainContext
        let rows = try context.fetch(
            FetchDescriptor<CachedBudget>(predicate: #Predicate { $0.homeID == homeID })
        )
        for row in rows where row.isDirty
            && row.category.caseInsensitiveCompare(category) == .orderedSame
            && Calendar.current.isDate(row.month, equalTo: month, toGranularity: .month) {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    func clearCategoryDirty(categoryID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedCustomCategory>(predicate: #Predicate { $0.id == categoryID })
        ).first {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    func clearCategoryDirty(homeID: UUID, name: String) throws {
        let context = container.mainContext
        let rows = try context.fetch(
            FetchDescriptor<CachedCustomCategory>(predicate: #Predicate { $0.homeID == homeID })
        )
        for row in rows where row.isDirty && row.name.caseInsensitiveCompare(name) == .orderedSame {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    // MARK: Repository protocol conformance

    func upsertLocal(_ items: [Budget]) throws {
        guard let homeID = items.first?.homeID else { return }
        try upsertLocal(items, homeID: homeID)
    }
}

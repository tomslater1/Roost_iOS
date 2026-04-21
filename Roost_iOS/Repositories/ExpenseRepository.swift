import Foundation
import SwiftData

// MARK: - ExpenseRepository
//
// Cache-first reads for the Expenses domain. Returns the `ExpenseWithSplits`
// shape that Money ViewModels consume, joined in memory from `CachedExpense`
// + `CachedExpenseSplit`.
//
// Write path goes through `OfflineAwareWrite.enqueue(_:)` — see
// `ExpenseMutationHandler` for the replay side.
//
// Dirty-row policy: a `CachedExpense` whose `isDirty == true` is never
// overwritten by a server refresh until its pending mutation has drained.
// Splits follow the parent expense's dirty state rather than tracking their
// own — offline writes to an expense always carry the full split set in the
// mutation payload, so splits are atomic with the parent.

@MainActor
struct ExpenseRepository: Repository {
    typealias Model = ExpenseWithSplits

    private let container: ModelContainer
    private let service: ExpenseService

    init(container: ModelContainer? = nil, service: ExpenseService = ExpenseService()) {
        self.container = container ?? LocalDataManager.shared.container
        self.service = service
    }

    // MARK: Cache reads

    func loadCached(homeID: UUID) throws -> [ExpenseWithSplits] {
        let context = container.mainContext

        let expensePredicate = #Predicate<CachedExpense> { $0.homeID == homeID }
        let expensesDescriptor = FetchDescriptor<CachedExpense>(predicate: expensePredicate)
        let cachedExpenses = try context.fetch(expensesDescriptor)
        guard !cachedExpenses.isEmpty else { return [] }

        let expenseIDs = Set(cachedExpenses.map(\.id))
        let splitsDescriptor = FetchDescriptor<CachedExpenseSplit>(
            predicate: #Predicate { expenseIDs.contains($0.expenseID) }
        )
        let cachedSplits = try context.fetch(splitsDescriptor)
        let splitsByExpenseID = Dictionary(grouping: cachedSplits, by: \.expenseID)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        return cachedExpenses.map { row in
            ExpenseWithSplits(
                id: row.id,
                homeID: row.homeID,
                title: row.title,
                amount: row.amount,
                paidBy: row.paidBy,
                splitType: nil, // splitType is not cached separately today; splits drive UI
                category: row.category,
                notes: nil,
                incurredOn: dateFormatter.string(from: row.incurredOn),
                isRecurring: nil,
                createdAt: row.createdAt,
                expenseSplits: (splitsByExpenseID[row.id] ?? []).map { split in
                    ExpenseSplit(
                        id: split.id,
                        expenseID: split.expenseID,
                        userID: split.userID,
                        amount: split.amount,
                        settledAt: split.settledAt,
                        settled: split.settled
                    )
                }
            )
        }.sorted { $0.incurredOn > $1.incurredOn }
    }

    // MARK: Refresh

    func refresh(homeID: UUID) async throws {
        let fresh = try await service.fetchExpenses(for: homeID)
        try upsertLocal(fresh, homeID: homeID)
    }

    // MARK: Cache merge (server → cache, dirty-preserving)

    /// Upserts an authoritative server snapshot into the cache for the given
    /// home. Rows whose local copy is `isDirty == true` are preserved; any
    /// non-dirty local row whose ID is absent from `items` is deleted.
    func upsertLocal(_ items: [ExpenseWithSplits], homeID: UUID) throws {
        let context = container.mainContext
        let existing = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.homeID == homeID })
        )
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(items.map(\.id))
        let now = Date()

        // Drop stale non-dirty rows (they're gone server-side).
        for cached in existing where !incomingIDs.contains(cached.id) && !cached.isDirty {
            // Also remove that expense's splits.
            let expenseID = cached.id
            let staleSplits = try context.fetch(
                FetchDescriptor<CachedExpenseSplit>(predicate: #Predicate { $0.expenseID == expenseID })
            )
            for split in staleSplits where !split.isDirty { context.delete(split) }
            context.delete(cached)
        }

        for item in items {
            let incurredOn = item.incurredOnDate ?? Date()
            if let row = existingByID[item.id] {
                if row.isDirty { continue } // local write wins until drain
                row.homeID = item.homeID
                row.title = item.title
                row.amount = item.amount
                row.paidBy = item.paidBy
                row.category = item.category
                row.incurredOn = incurredOn
                row.createdAt = item.createdAt
                row.lastSyncedAt = now
                row.pendingOperation = nil
            } else {
                let fresh = CachedExpense(
                    id: item.id,
                    homeID: item.homeID,
                    title: item.title,
                    amount: item.amount,
                    paidBy: item.paidBy,
                    category: item.category,
                    incurredOn: incurredOn,
                    createdAt: item.createdAt
                )
                fresh.lastSyncedAt = now
                context.insert(fresh)
            }

            try replaceSplits(for: item.id, with: item.expenseSplits, context: context, now: now)
        }

        try context.save()
    }

    // MARK: - Optimistic cache writes (used by VMs before the queue drains)

    /// Applies an optimistic insert/update to the local cache and marks the
    /// row dirty so a server refresh won't clobber it before drain.
    func applyOptimisticUpsert(
        expense: Expense,
        splits: [ExpenseSplit],
        pendingOperation: String
    ) throws {
        let context = container.mainContext
        let expenseID = expense.id
        let existing = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == expenseID })
        ).first

        let incurredOn = expense.incurredOnDate ?? Date()

        if let row = existing {
            row.homeID = expense.homeID
            row.title = expense.title
            row.amount = expense.amount
            row.paidBy = expense.paidBy
            row.category = expense.category
            row.incurredOn = incurredOn
            row.isDirty = true
            row.pendingOperation = pendingOperation
        } else {
            let fresh = CachedExpense(
                id: expense.id,
                homeID: expense.homeID,
                title: expense.title,
                amount: expense.amount,
                paidBy: expense.paidBy,
                category: expense.category,
                incurredOn: incurredOn,
                createdAt: expense.createdAt
            )
            fresh.isDirty = true
            fresh.pendingOperation = pendingOperation
            context.insert(fresh)
        }

        try replaceSplits(for: expense.id, with: splits, context: context, now: Date(), markDirty: true)
        try context.save()
    }

    /// Optimistic delete — removes the row from the cache immediately. The
    /// mutation payload carries the ID so replay still targets the server.
    func applyOptimisticDelete(expenseID: UUID) throws {
        let context = container.mainContext
        let expense = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == expenseID })
        ).first
        if let expense { context.delete(expense) }
        let splits = try context.fetch(
            FetchDescriptor<CachedExpenseSplit>(predicate: #Predicate { $0.expenseID == expenseID })
        )
        for split in splits { context.delete(split) }
        try context.save()
    }

    /// Marks the splits on an expense as "settlement pending" so the UI can
    /// show a pending treatment without flipping to the settled state.
    func applyOptimisticSettlement(affectedExpenseIDs: [UUID]) throws {
        let context = container.mainContext
        for id in affectedExpenseIDs {
            if let row = try context.fetch(
                FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == id })
            ).first {
                row.isDirty = true
                row.pendingOperation = "settlement"
            }
        }
        try context.save()
    }

    // MARK: - Drain hooks (called by handler after successful replay)

    /// Clears the dirty + pendingOperation flags on a single expense row so a
    /// subsequent `refresh()` can overwrite its fields with authoritative
    /// server state. Called after a successful create/update replay.
    func clearDirty(expenseID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == expenseID })
        ).first {
            row.isDirty = false
            row.pendingOperation = nil
        }
        let splits = try context.fetch(
            FetchDescriptor<CachedExpenseSplit>(predicate: #Predicate { $0.expenseID == expenseID })
        )
        for split in splits {
            split.isDirty = false
            split.pendingOperation = nil
        }
        try context.save()
    }

    /// Clears any "settlement" dirty markers across a home after a settle-up
    /// RPC has succeeded. The subsequent refresh pulls authoritative split
    /// state (settledAt timestamps) from the server.
    func clearSettlementPending(homeID: UUID) throws {
        let context = container.mainContext
        let rows = try context.fetch(
            FetchDescriptor<CachedExpense>(
                predicate: #Predicate { $0.homeID == homeID && $0.pendingOperation == "settlement" }
            )
        )
        for row in rows {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    // MARK: Private

    private func replaceSplits(
        for expenseID: UUID,
        with splits: [ExpenseSplit],
        context: ModelContext,
        now: Date,
        markDirty: Bool = false
    ) throws {
        let existing = try context.fetch(
            FetchDescriptor<CachedExpenseSplit>(predicate: #Predicate { $0.expenseID == expenseID })
        )
        for split in existing { context.delete(split) }
        for split in splits {
            let fresh = CachedExpenseSplit(
                id: split.id,
                expenseID: split.expenseID,
                userID: split.userID,
                amount: split.amount,
                settledAt: split.settledAt,
                settled: split.settled ?? (split.settledAt != nil)
            )
            fresh.lastSyncedAt = markDirty ? nil : now
            fresh.isDirty = markDirty
            context.insert(fresh)
        }
    }

    // MARK: Repository conformance fallback

    /// Convenience overload to satisfy the `Repository` protocol's
    /// `refresh(homeID:)` without forcing a second `upsertLocal(_:homeID:)`
    /// signature. We re-expose `upsertLocal` here under the protocol-expected
    /// shape by picking the `homeID` off the first row.
    func upsertLocal(_ items: [ExpenseWithSplits]) throws {
        guard let homeID = items.first?.homeID else { return }
        try upsertLocal(items, homeID: homeID)
    }
}

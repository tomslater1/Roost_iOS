import Testing
import Foundation
import SwiftData
@testable import Roost

/// Covers the Phase 2 Expenses migration contract:
///   - cache-first reads join CachedExpense + CachedExpenseSplit
///   - server refresh preserves dirty rows (queued offline writes win until drain)
///   - optimistic writes set the expected dirty/pendingOperation flags
///   - drain hooks (`clearDirty`, `clearSettlementPending`) reset the flags
@MainActor
struct ExpenseRepositoryTests {

    // MARK: Helpers

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            CachedExpense.self,
            CachedExpenseSplit.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private func makeRepository() throws -> (ExpenseRepository, ModelContainer) {
        let container = try makeInMemoryContainer()
        return (ExpenseRepository(container: container, service: ExpenseService()), container)
    }

    private func sampleExpense(
        id: UUID = UUID(),
        homeID: UUID,
        title: String = "Groceries",
        amount: Decimal = 20,
        paidBy: UUID = UUID(),
        category: String? = "food",
        date: Date = Date()
    ) -> ExpenseWithSplits {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return ExpenseWithSplits(
            id: id,
            homeID: homeID,
            title: title,
            amount: amount,
            paidBy: paidBy,
            splitType: "equal",
            category: category,
            notes: nil,
            incurredOn: formatter.string(from: date),
            isRecurring: nil,
            createdAt: Date(),
            expenseSplits: []
        )
    }

    // MARK: Tests

    @Test func upsertLocalInsertsNewRows() throws {
        let (repo, _) = try makeRepository()
        let homeID = UUID()
        try repo.upsertLocal([sampleExpense(homeID: homeID)], homeID: homeID)

        #expect(try repo.loadCached(homeID: homeID).count == 1)
    }

    @Test func upsertLocalDeletesStaleNonDirtyRows() throws {
        let (repo, _) = try makeRepository()
        let homeID = UUID()
        let keep = sampleExpense(homeID: homeID, title: "Rent")
        let drop = sampleExpense(homeID: homeID, title: "Taxi")
        try repo.upsertLocal([keep, drop], homeID: homeID)

        // Server now only returns `keep`. `drop` is not dirty → should be gone.
        try repo.upsertLocal([keep], homeID: homeID)
        let after = try repo.loadCached(homeID: homeID)
        #expect(after.count == 1)
        #expect(after.first?.id == keep.id)
    }

    @Test func upsertLocalPreservesDirtyRows() throws {
        let (repo, _) = try makeRepository()
        let homeID = UUID()
        let rowID = UUID()
        let paidBy = UUID()

        // Write an optimistic dirty row (offline create).
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: Date())
        try repo.applyOptimisticUpsert(
            expense: Expense(
                id: rowID, homeID: homeID, title: "Local draft",
                amount: 10, paidBy: paidBy, splitType: "equal",
                category: nil, notes: nil, incurredOn: dateString,
                isRecurring: nil, createdAt: Date()
            ),
            splits: [],
            pendingOperation: "create"
        )

        // A server refresh arrives with none of that row — naive code would
        // wipe it. Our policy keeps it because isDirty == true.
        try repo.upsertLocal([], homeID: homeID)
        let after = try repo.loadCached(homeID: homeID)
        #expect(after.count == 1)
        #expect(after.first?.title == "Local draft")
    }

    @Test func clearDirtyAllowsSubsequentRefreshToOverwrite() throws {
        let (repo, container) = try makeRepository()
        let homeID = UUID()
        let rowID = UUID()
        let paidBy = UUID()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: Date())

        try repo.applyOptimisticUpsert(
            expense: Expense(
                id: rowID, homeID: homeID, title: "Draft",
                amount: 10, paidBy: paidBy, splitType: "equal",
                category: nil, notes: nil, incurredOn: dateString,
                isRecurring: nil, createdAt: Date()
            ),
            splits: [],
            pendingOperation: "create"
        )
        // Drain succeeded — handler clears the dirty flag.
        try repo.clearDirty(expenseID: rowID)

        let context = container.mainContext
        let stored = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == rowID })
        ).first
        #expect(stored?.isDirty == false)
        #expect(stored?.pendingOperation == nil)

        // Server now returns an updated title.
        let updated = sampleExpense(id: rowID, homeID: homeID, title: "Server title", paidBy: paidBy)
        try repo.upsertLocal([updated], homeID: homeID)
        let after = try repo.loadCached(homeID: homeID).first
        #expect(after?.title == "Server title")
    }

    @Test func applyOptimisticDeleteRemovesExpenseAndSplits() throws {
        let (repo, container) = try makeRepository()
        let homeID = UUID()
        let rowID = UUID()
        let paidBy = UUID()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: Date())

        try repo.applyOptimisticUpsert(
            expense: Expense(
                id: rowID, homeID: homeID, title: "With splits",
                amount: 30, paidBy: paidBy, splitType: "equal",
                category: nil, notes: nil, incurredOn: dateString,
                isRecurring: nil, createdAt: Date()
            ),
            splits: [
                ExpenseSplit(id: UUID(), expenseID: rowID, userID: paidBy, amount: 15, settledAt: Date(), settled: true),
                ExpenseSplit(id: UUID(), expenseID: rowID, userID: UUID(), amount: 15, settledAt: nil, settled: false),
            ],
            pendingOperation: "create"
        )

        try repo.applyOptimisticDelete(expenseID: rowID)

        let context = container.mainContext
        let remainingExpense = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == rowID })
        )
        let remainingSplits = try context.fetch(
            FetchDescriptor<CachedExpenseSplit>(predicate: #Predicate { $0.expenseID == rowID })
        )
        #expect(remainingExpense.isEmpty)
        #expect(remainingSplits.isEmpty)
    }

    @Test func applyOptimisticSettlementMarksAffectedRowsPending() throws {
        let (repo, container) = try makeRepository()
        let homeID = UUID()
        let a = UUID(), b = UUID()
        try repo.upsertLocal([
            sampleExpense(id: a, homeID: homeID),
            sampleExpense(id: b, homeID: homeID),
        ], homeID: homeID)

        try repo.applyOptimisticSettlement(affectedExpenseIDs: [a])

        let context = container.mainContext
        let rowA = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == a })
        ).first
        let rowB = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == b })
        ).first
        #expect(rowA?.pendingOperation == "settlement")
        #expect(rowA?.isDirty == true)
        #expect(rowB?.pendingOperation == nil)
        #expect(rowB?.isDirty == false)

        try repo.clearSettlementPending(homeID: homeID)
        let clearedA = try context.fetch(
            FetchDescriptor<CachedExpense>(predicate: #Predicate { $0.id == a })
        ).first
        #expect(clearedA?.pendingOperation == nil)
        #expect(clearedA?.isDirty == false)
    }

    @Test func loadCachedSortsByIncurredDateDescending() throws {
        let (repo, _) = try makeRepository()
        let homeID = UUID()
        let cal = Calendar.current
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!

        try repo.upsertLocal([
            sampleExpense(homeID: homeID, title: "Old", date: weekAgo),
            sampleExpense(homeID: homeID, title: "Today", date: today),
            sampleExpense(homeID: homeID, title: "Yesterday", date: yesterday),
        ], homeID: homeID)

        let rows = try repo.loadCached(homeID: homeID)
        #expect(rows.map(\.title) == ["Today", "Yesterday", "Old"])
    }
}

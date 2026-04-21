import Foundation
import SwiftData

// MARK: - SavingsGoalRepository
//
// Cache-first reads for the Savings Goals domain. `CachedSavingsGoal` stores
// the full row; no joined tables.
//
// Offline operations (ones the mutation queue replays):
//   - "create"           — insert a goal the user added offline
//   - "delete"           — delete a goal
//   - "complete"         — toggle is_complete + completed_at
//   - "add_contribution" — `savedAmount += delta` (additive, LWW-safe)
//
// Not handled by the queue (require network at call time):
//   - setGoalContribution / removeGoalContribution — these mutate a second
//     domain (budget_template_lines) and the VM blocks them when offline.

@MainActor
struct SavingsGoalRepository: Repository {
    typealias Model = SavingsGoal

    private let container: ModelContainer
    private let service: SavingsGoalsService

    init(container: ModelContainer? = nil, service: SavingsGoalsService = SavingsGoalsService()) {
        self.container = container ?? LocalDataManager.shared.container
        self.service = service
    }

    // MARK: Cache reads

    func loadCached(homeID: UUID) throws -> [SavingsGoal] {
        let context = container.mainContext
        let rows = try context.fetch(
            FetchDescriptor<CachedSavingsGoal>(
                predicate: #Predicate { $0.homeID == homeID },
                sortBy: [
                    SortDescriptor(\.sortOrder, order: .forward),
                    SortDescriptor(\.createdAt, order: .forward)
                ]
            )
        )
        return rows.map { row in
            SavingsGoal(
                id: row.id,
                homeId: row.homeID,
                name: row.name,
                targetAmount: row.targetAmount,
                savedAmount: row.savedAmount,
                colour: row.colour,
                icon: row.icon,
                targetDate: row.targetDate,
                isComplete: row.isComplete,
                completedAt: row.completedAt,
                sortOrder: row.sortOrder,
                monthlyContribution: row.monthlyContribution,
                contributionDay: row.contributionDay,
                budgetLineId: row.budgetLineID,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
        }
    }

    // MARK: Refresh

    func refresh(homeID: UUID) async throws {
        let fresh = try await service.fetchGoals(homeId: homeID)
        try upsertLocal(fresh, homeID: homeID)
    }

    // MARK: Cache merge

    func upsertLocal(_ items: [SavingsGoal], homeID: UUID) throws {
        let context = container.mainContext
        let existing = try context.fetch(
            FetchDescriptor<CachedSavingsGoal>(predicate: #Predicate { $0.homeID == homeID })
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
                row.targetAmount = item.targetAmount
                row.savedAmount = item.savedAmount
                row.colour = item.colour
                row.icon = item.icon
                row.targetDate = item.targetDate
                row.isComplete = item.isComplete
                row.completedAt = item.completedAt
                row.sortOrder = item.sortOrder
                row.monthlyContribution = item.monthlyContribution
                row.contributionDay = item.contributionDay
                row.budgetLineID = item.budgetLineId
                row.updatedAt = item.updatedAt
                row.lastSyncedAt = now
                row.pendingOperation = nil
            } else {
                let fresh = CachedSavingsGoal(from: item)
                fresh.lastSyncedAt = now
                context.insert(fresh)
            }
        }

        try context.save()
    }

    // MARK: Optimistic writes

    @discardableResult
    func applyOptimisticInsert(_ goal: SavingsGoal, pendingOperation: String = "create") throws -> SavingsGoal {
        let context = container.mainContext
        let fresh = CachedSavingsGoal(from: goal)
        fresh.isDirty = true
        fresh.pendingOperation = pendingOperation
        context.insert(fresh)
        try context.save()
        return goal
    }

    func applyOptimisticDelete(goalID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedSavingsGoal>(predicate: #Predicate { $0.id == goalID })
        ).first {
            context.delete(row)
        }
        try context.save()
    }

    /// Applies an additive update to the local savedAmount, capping at the
    /// target. Marks the goal complete locally if it now meets the target.
    func applyOptimisticAddContribution(goalID: UUID, delta: Decimal) throws {
        let context = container.mainContext
        guard let row = try context.fetch(
            FetchDescriptor<CachedSavingsGoal>(predicate: #Predicate { $0.id == goalID })
        ).first else { return }
        let newSaved = min(row.targetAmount, row.savedAmount + delta)
        row.savedAmount = newSaved
        if newSaved >= row.targetAmount, !row.isComplete {
            row.isComplete = true
            row.completedAt = Date()
        }
        row.isDirty = true
        row.pendingOperation = "add_contribution"
        try context.save()
    }

    func applyOptimisticComplete(goalID: UUID) throws {
        let context = container.mainContext
        guard let row = try context.fetch(
            FetchDescriptor<CachedSavingsGoal>(predicate: #Predicate { $0.id == goalID })
        ).first else { return }
        row.isComplete = true
        row.completedAt = row.completedAt ?? Date()
        row.isDirty = true
        row.pendingOperation = "complete"
        try context.save()
    }

    // MARK: Drain hooks

    func clearDirty(goalID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedSavingsGoal>(predicate: #Predicate { $0.id == goalID })
        ).first {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    // MARK: Repository conformance

    func upsertLocal(_ items: [SavingsGoal]) throws {
        guard let homeID = items.first?.homeId else { return }
        try upsertLocal(items, homeID: homeID)
    }
}

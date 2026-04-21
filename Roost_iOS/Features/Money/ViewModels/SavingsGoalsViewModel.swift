import Foundation
import Observation
import Realtime
import SwiftUI

@MainActor
@Observable
final class SavingsGoalsViewModel {

    var goals: [SavingsGoal] = []
    var isLoading = false
    var error: Error?

    @ObservationIgnored
    private let service = SavingsGoalsService()

    @ObservationIgnored
    private let repository = SavingsGoalRepository()

    @ObservationIgnored
    private var subscriptionId: UUID?

    @ObservationIgnored
    private var subscribedHomeId: UUID?

    // MARK: - Computed

    var activeGoals: [SavingsGoal] {
        goals.filter { !$0.isCompleted }
    }

    var completedGoals: [SavingsGoal] {
        goals.filter(\.isCompleted)
    }

    var totalMonthlyContribution: Decimal {
        activeGoals.compactMap(\.monthlyContribution).reduce(0, +)
    }

    // MARK: - Load

    func load(homeId: UUID) async {
        isLoading = true
        error = nil

        // Cache-first paint.
        do {
            goals = try repository.loadCached(homeID: homeId)
        } catch {
            // Cache miss is not fatal.
        }

        do {
            try await repository.refresh(homeID: homeId)
            goals = try repository.loadCached(homeID: homeId)
        } catch {
            if !isCancellation(error) { self.error = error }
        }
        isLoading = false
    }

    // MARK: - CRUD

    @discardableResult
    func addGoal(_ data: CreateSavingsGoal) async throws -> SavingsGoal {
        let clientID = UUID()
        let now = Date()
        let optimistic = SavingsGoal(
            id: clientID,
            homeId: data.homeId,
            name: data.name,
            targetAmount: data.targetAmount,
            savedAmount: data.savedAmount,
            colour: data.colour,
            icon: data.icon,
            targetDate: data.targetDate,
            isComplete: false,
            completedAt: nil,
            sortOrder: data.sortOrder,
            monthlyContribution: data.monthlyContribution,
            contributionDay: data.contributionDay,
            budgetLineId: nil,
            createdAt: now,
            updatedAt: now
        )
        try repository.applyOptimisticInsert(optimistic)
        goals.append(optimistic)

        let payload = SavingsGoalCreatePayload(
            goal: InsertSavingsGoal(
                id: clientID,
                homeId: data.homeId,
                name: data.name,
                targetAmount: data.targetAmount,
                savedAmount: data.savedAmount,
                colour: data.colour,
                icon: data.icon,
                targetDate: data.targetDate,
                sortOrder: data.sortOrder,
                monthlyContribution: data.monthlyContribution,
                contributionDay: data.contributionDay
            )
        )
        try OfflineAwareWrite.enqueue(
            .init(
                entityType: "savings_goal",
                operation: "create",
                targetID: clientID,
                homeID: data.homeId,
                payload: try JSONEncoder.mutation.encode(payload)
            )
        )
        return optimistic
    }

    func addToGoal(id: UUID, amount: Decimal) async throws {
        // Optimistic additive update (capped at target locally).
        try repository.applyOptimisticAddContribution(goalID: id, delta: amount)
        if let idx = goals.firstIndex(where: { $0.id == id }) {
            let current = goals[idx]
            let newSaved = min(current.targetAmount, current.savedAmount + amount)
            let nowCompleted = newSaved >= current.targetAmount
            goals[idx] = SavingsGoal(
                id: current.id,
                homeId: current.homeId,
                name: current.name,
                targetAmount: current.targetAmount,
                savedAmount: newSaved,
                colour: current.colour,
                icon: current.icon,
                targetDate: current.targetDate,
                isComplete: nowCompleted || current.isComplete,
                completedAt: (nowCompleted && !current.isComplete) ? Date() : current.completedAt,
                sortOrder: current.sortOrder,
                monthlyContribution: current.monthlyContribution,
                contributionDay: current.contributionDay,
                budgetLineId: current.budgetLineId,
                createdAt: current.createdAt,
                updatedAt: Date()
            )
        }

        let homeId = goals.first(where: { $0.id == id })?.homeId ?? UUID()
        let payload = SavingsGoalContributionPayload(goalID: id, delta: amount, homeID: homeId)
        try OfflineAwareWrite.enqueue(
            .init(
                entityType: "savings_goal",
                operation: "add_contribution",
                targetID: id,
                homeID: homeId,
                payload: try JSONEncoder.mutation.encode(payload)
            )
        )
    }

    func updateGoal(id: UUID, updates: [String: AnyJSON]) async throws {
        let updated = try await service.updateGoal(id: id, updates: updates)
        if let idx = goals.firstIndex(where: { $0.id == id }) {
            goals[idx] = updated
        }
    }

    func completeGoal(id: UUID) async throws {
        // If the goal has a linked budget-template contribution, clearing it
        // mutates another domain and needs the network; perform it online only.
        if let goal = goals.first(where: { $0.id == id }),
           let budgetLineId = goal.budgetLineId {
            let cleared = try await service.removeGoalContribution(goalId: id, budgetLineId: budgetLineId)
            if let idx = goals.firstIndex(where: { $0.id == id }) {
                goals[idx] = cleared
            }
        }

        try repository.applyOptimisticComplete(goalID: id)
        let homeId = goals.first(where: { $0.id == id })?.homeId ?? UUID()
        if let idx = goals.firstIndex(where: { $0.id == id }) {
            var g = goals[idx]
            g.isComplete = true
            g.completedAt = g.completedAt ?? Date()
            goals[idx] = g
        }

        try OfflineAwareWrite.enqueue(
            .init(
                entityType: "savings_goal",
                operation: "complete",
                targetID: id,
                homeID: homeId,
                payload: Data()
            )
        )
    }

    func deleteGoal(id: UUID) async throws {
        let homeId = goals.first(where: { $0.id == id })?.homeId ?? UUID()
        try repository.applyOptimisticDelete(goalID: id)
        goals.removeAll { $0.id == id }

        try OfflineAwareWrite.enqueue(
            .init(
                entityType: "savings_goal",
                operation: "delete",
                targetID: id,
                homeID: homeId,
                payload: Data()
            )
        )
    }

    func setGoalContribution(
        goalId: UUID,
        homeId: UUID,
        existingBudgetLineId: UUID?,
        name: String,
        amount: Decimal,
        contributionDay: Int
    ) async throws {
        let updated = try await service.setGoalContribution(
            goalId: goalId,
            homeId: homeId,
            existingBudgetLineId: existingBudgetLineId,
            name: name,
            amount: amount,
            contributionDay: contributionDay
        )
        if let idx = goals.firstIndex(where: { $0.id == goalId }) {
            goals[idx] = updated
        }
    }

    /// Clears monthly_contribution and contribution_day on the goal without touching the budget template line.
    func clearContributionFields(goalId: UUID) async throws {
        let updated = try await service.updateGoal(id: goalId, updates: [
            "monthly_contribution": AnyJSON.null,
            "contribution_day": AnyJSON.null
        ])
        if let idx = goals.firstIndex(where: { $0.id == goalId }) {
            goals[idx] = updated
        }
    }

    func removeGoalContribution(goalId: UUID, budgetLineId: UUID) async throws {
        let updated = try await service.removeGoalContribution(goalId: goalId, budgetLineId: budgetLineId)
        if let idx = goals.firstIndex(where: { $0.id == goalId }) {
            goals[idx] = updated
        }
    }

    // MARK: - Realtime

    func startRealtime(homeId: UUID) async {
        if let existing = subscribedHomeId, existing != homeId { await stopRealtime() }
        guard subscriptionId == nil else { return }
        subscribedHomeId = homeId

        subscriptionId = await RealtimeManager.shared.subscribe(
            table: "savings_goals",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self, let hid = self.subscribedHomeId else { return }
            await self.refresh(homeId: hid)
        }
    }

    func stopRealtime() async {
        if let id = subscriptionId {
            await RealtimeManager.shared.unsubscribe(table: "savings_goals", callbackId: id)
            subscriptionId = nil
        }
        subscribedHomeId = nil
    }

    // MARK: - Private

    private func refresh(homeId: UUID) async {
        do {
            try await repository.refresh(homeID: homeId)
            goals = try repository.loadCached(homeID: homeId)
        } catch {
            // Silent on realtime refresh — keep current state.
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled ||
        (error as NSError).code == NSURLErrorCancelled
    }
}

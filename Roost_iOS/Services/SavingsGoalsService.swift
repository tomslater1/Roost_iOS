import Foundation
import Supabase

struct SavingsGoalsService {

    func fetchGoals(homeId: UUID) async throws -> [SavingsGoal] {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("savings_goals")
            .select()
            .eq("home_id", value: homeId)
            .order("sort_order")
            .order("created_at")
            .execute()
            .value
    }

    func addGoal(_ goal: CreateSavingsGoal) async throws -> SavingsGoal {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("savings_goals")
            .insert(goal)
            .select()
            .single()
            .execute()
            .value
    }

    /// Insert path that accepts a client-supplied UUID. Used by the offline
    /// mutation queue so local cache rows and server rows share a PK.
    func insertGoal(_ goal: InsertSavingsGoal) async throws -> SavingsGoal {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("savings_goals")
            .insert(goal)
            .select()
            .single()
            .execute()
            .value
    }

    /// Adds an amount to current_amount by fetching the current value first,
    /// then updating with the new total (PostgREST does not support column increments).
    func addToGoal(id: UUID, amount: Decimal) async throws -> SavingsGoal {
        let client = try SupabaseClientProvider.shared.requireClient()
        let current: SavingsGoal = try await client
            .from("savings_goals")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        let newSaved = min(current.targetAmount, current.savedAmount + amount)
        var updates: [String: AnyJSON] = [
            "current_amount": AnyJSON.double(NSDecimalNumber(decimal: newSaved).doubleValue)
        ]
        if newSaved >= current.targetAmount, !current.isCompleted {
            if let budgetLineId = current.budgetLineId {
                try await BudgetTemplateService().removeLine(id: budgetLineId)
                updates["monthly_contribution"] = AnyJSON.null
                updates["contribution_day"] = AnyJSON.null
                updates["budget_line_id"] = AnyJSON.null
            }
            updates["is_complete"] = AnyJSON.bool(true)
            updates["completed_at"] = AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
        }
        return try await client
            .from("savings_goals")
            .update(updates)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func updateGoal(id: UUID, updates: [String: AnyJSON]) async throws -> SavingsGoal {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("savings_goals")
            .update(updates)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func completeGoal(id: UUID) async throws -> SavingsGoal {
        let client = try SupabaseClientProvider.shared.requireClient()
        let now = ISO8601DateFormatter().string(from: Date())
        return try await client
            .from("savings_goals")
            .update([
                "is_complete": AnyJSON.bool(true),
                "completed_at": AnyJSON.string(now)
            ])
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteGoal(id: UUID) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        try await client
            .from("savings_goals")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// Creates or updates the budget template line linked to this goal's monthly contribution,
    /// then stores the line ID back on the savings_goal row.
    func setGoalContribution(
        goalId: UUID,
        homeId: UUID,
        existingBudgetLineId: UUID?,
        name: String,
        amount: Decimal,
        contributionDay: Int
    ) async throws -> SavingsGoal {
        let client = try SupabaseClientProvider.shared.requireClient()
        let templateService = BudgetTemplateService()

        if let lineId = existingBudgetLineId {
            // Update existing line
            _ = try await templateService.updateLine(
                id: lineId,
                updates: UpdateBudgetLine(
                    name: "\(name) — savings",
                    amount: amount,
                    budgetType: "envelope",
                    sectionGroup: "savings",
                    dayOfMonth: contributionDay
                )
            )
        } else {
            // Create a visible line under the Savings allocation section on the budgets page.
            let newLine = CreateBudgetLine(
                homeId: homeId,
                name: "\(name) — savings",
                amount: amount,
                budgetType: "envelope",
                sectionGroup: "savings",
                dayOfMonth: contributionDay,
                isAnnual: false,
                annualAmount: nil,
                rolloverEnabled: false,
                ownership: "shared",
                member1Percentage: 50,
                note: nil,
                sortOrder: 999,
                isActive: true
            )
            let created = try await templateService.addLine(newLine)
            // Store budget_line_id on the goal
            return try await client
                .from("savings_goals")
                .update([
                    "monthly_contribution": AnyJSON.double(NSDecimalNumber(decimal: amount).doubleValue),
                    "contribution_day": AnyJSON.double(Double(contributionDay)),
                    "budget_line_id": AnyJSON.string(created.id.uuidString)
                ])
                .eq("id", value: goalId)
                .select()
                .single()
                .execute()
                .value
        }

        // Update the goal row contribution fields
        return try await client
            .from("savings_goals")
            .update([
                "monthly_contribution": AnyJSON.double(NSDecimalNumber(decimal: amount).doubleValue),
                "contribution_day": AnyJSON.double(Double(contributionDay))
            ])
            .eq("id", value: goalId)
            .select()
            .single()
            .execute()
            .value
    }

    /// Deactivates the linked budget template line and clears contribution fields on the goal.
    func removeGoalContribution(goalId: UUID, budgetLineId: UUID) async throws -> SavingsGoal {
        let client = try SupabaseClientProvider.shared.requireClient()
        let templateService = BudgetTemplateService()
        try await templateService.removeLine(id: budgetLineId)
        return try await client
            .from("savings_goals")
            .update([
                "monthly_contribution": AnyJSON.null,
                "contribution_day": AnyJSON.null,
                "budget_line_id": AnyJSON.null
            ])
            .eq("id", value: goalId)
            .select()
            .single()
            .execute()
            .value
    }
}

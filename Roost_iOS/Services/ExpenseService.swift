import Foundation
import Supabase

struct ExpenseService {
    func fetchExpenses(for homeID: UUID) async throws -> [ExpenseWithSplits] {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("expenses")
            .select("*, expense_splits(*)")
            .eq("home_id", value: homeID)
            .order("date", ascending: false)
            .execute()
            .value
    }

    /// Insert path that accepts a client-supplied UUID. Used by the offline
    /// mutation queue so local cache rows and server rows share a PK.
    func insertExpense(_ expense: InsertExpense, splits: [CreateExpenseSplit]) async throws -> Expense {
        let client = try SupabaseClientProvider.shared.requireClient()

        let created: Expense = try await client
            .from("expenses")
            .insert(expense)
            .select()
            .single()
            .execute()
            .value

        if !splits.isEmpty {
            let splitsWithExpenseId = splits.map { split in
                InsertExpenseSplit(
                    expenseID: created.id,
                    userID: split.userID,
                    amount: split.amount,
                    settledAt: split.settledAt
                )
            }
            try await client
                .from("expense_splits")
                .insert(splitsWithExpenseId)
                .execute()
        }

        return created
    }

    func createExpense(_ expense: CreateExpense, splits: [CreateExpenseSplit]) async throws -> Expense {
        let client = try SupabaseClientProvider.shared.requireClient()

        // Insert the expense and get back the server-generated row
        let created: Expense = try await client
            .from("expenses")
            .insert(expense)
            .select()
            .single()
            .execute()
            .value

        // Insert splits with the new expense ID
        if !splits.isEmpty {
            let splitsWithExpenseId = splits.map { split in
                InsertExpenseSplit(
                    expenseID: created.id,
                    userID: split.userID,
                    amount: split.amount,
                    settledAt: split.settledAt
                )
            }
            try await client
                .from("expense_splits")
                .insert(splitsWithExpenseId)
                .execute()
        }

        return created
    }

    func updateExpense(_ expense: Expense) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        var payload: [String: AnyJSON] = [
            "title": .string(expense.title),
            "amount": .double(NSDecimalNumber(decimal: expense.amount).doubleValue),
            "paid_by": .string(expense.paidBy.uuidString),
            "date": .string(expense.incurredOn)
        ]

        payload["split_type"] = expense.splitType.map(AnyJSON.string) ?? .null
        payload["category"] = expense.category.map(AnyJSON.string) ?? .null
        payload["notes"] = expense.notes.map(AnyJSON.string) ?? .null
        payload["is_recurring"] = expense.isRecurring.map(AnyJSON.bool) ?? .null

        try await client
            .from("expenses")
            .update(payload)
            .eq("id", value: expense.id)
            .execute()
    }

    func replaceExpense(_ expense: Expense, splits: [CreateExpenseSplit]) async throws -> ExpenseWithSplits {
        let client = try SupabaseClientProvider.shared.requireClient()

        try await updateExpense(expense)

        try await client
            .from("expense_splits")
            .delete()
            .eq("expense_id", value: expense.id)
            .execute()

        if !splits.isEmpty {
            let splitsWithExpenseId = splits.map { split in
                InsertExpenseSplit(
                    expenseID: expense.id,
                    userID: split.userID,
                    amount: split.amount,
                    settledAt: split.settledAt
                )
            }
            try await client
                .from("expense_splits")
                .insert(splitsWithExpenseId)
                .execute()
        }

        return try await client
            .from("expenses")
            .select("*, expense_splits(*)")
            .eq("id", value: expense.id)
            .single()
            .execute()
            .value
    }

    func deleteExpense(id: UUID) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        try await client
            .from("expenses")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func settleUp(homeID: UUID, paidBy: UUID, paidTo: UUID, amount: Decimal, note: String? = nil) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        var params: [String: AnyJSON] = [
            "home_id": .string(homeID.uuidString),
            "paid_by": .string(paidBy.uuidString),
            "paid_to": .string(paidTo.uuidString),
            "settlement_amount": .double(NSDecimalNumber(decimal: amount).doubleValue),
        ]
        if let note {
            params["settlement_note"] = .string(note)
        }
        try await client
            .rpc("settle_up", params: params)
            .execute()
    }
}

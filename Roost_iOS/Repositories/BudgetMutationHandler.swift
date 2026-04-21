import Foundation

// MARK: - BudgetMutationHandler
//
// Replays queued budget mutations against the server.
//
// Operations:
//   - "upsert"         — entityType "budget";           payload BudgetUpsertPayload
//   - "delete"         — entityType "budget";           no payload (targetID = budget.id)
//   - "category_create"— entityType "budget_category";  payload CustomCategoryCreatePayload
//   - "category_delete"— entityType "budget_category";  no payload (targetID = category.id)
//
// Replay order: the outbox drains FIFO by `createdAt`, so a category create
// that precedes a budget upsert referencing that category's name replays in
// the right order. Budgets reference categories by name (string), not by FK,
// so orphaned references are not possible.

// MARK: - Payloads

struct BudgetUpsertPayload: Codable {
    /// Local UUID we optimistically inserted — used to clear the dirty flag
    /// on the right row after replay, even though the server keys by the
    /// composite natural key `(home_id, category, month)`.
    var localID: UUID
    var homeID: UUID
    var category: String
    var amount: Decimal
    var month: Date
}

struct CustomCategoryCreatePayload: Codable {
    var localID: UUID
    var homeID: UUID
    var name: String
    var emoji: String
    var color: String?
}

// MARK: - Budget handler

@MainActor
struct BudgetMutationHandler: MutationHandler {
    let entityType = "budget"

    private let service: BudgetService
    private let repository: BudgetRepository

    init(service: BudgetService? = nil, repository: BudgetRepository? = nil) {
        self.service = service ?? BudgetService()
        self.repository = repository ?? BudgetRepository()
    }

    func replay(_ mutation: PendingMutation) async throws {
        switch mutation.operation {
        case "upsert":
            try await replayUpsert(mutation)
        case "delete":
            try await replayDelete(mutation)
        default:
            throw MutationHandlerError.permanent("Unknown budget operation '\(mutation.operation)'.")
        }
    }

    private func replayUpsert(_ mutation: PendingMutation) async throws {
        let payload: BudgetUpsertPayload
        do {
            payload = try JSONDecoder.mutation.decode(BudgetUpsertPayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed budget upsert payload: \(error.localizedDescription)")
        }

        do {
            _ = try await service.upsertBudget(
                UpsertBudget(
                    homeID: payload.homeID,
                    category: payload.category,
                    amount: payload.amount,
                    month: payload.month
                )
            )
        } catch {
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't save budget.")
        }

        // Clear the dirty marker on the natural-key match (the server may
        // have issued a different UUID) then refresh authoritative state.
        try? repository.clearBudgetDirty(
            homeID: payload.homeID,
            category: payload.category,
            month: payload.month
        )
        try? repository.clearBudgetDirty(budgetID: payload.localID)
        try? await repository.refresh(homeID: payload.homeID)
    }

    private func replayDelete(_ mutation: PendingMutation) async throws {
        do {
            try await service.deleteBudget(id: mutation.targetID)
        } catch {
            if MutationErrorClassifier.isNotFound(error) {
                throw MutationHandlerError.reconciledByServer("Budget already deleted on server.")
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't delete budget.")
        }
        if let homeID = mutation.homeID {
            try? await repository.refresh(homeID: homeID)
        }
    }
}

// MARK: - Custom category handler

@MainActor
struct CustomCategoryMutationHandler: MutationHandler {
    let entityType = "budget_category"

    private let service: BudgetService
    private let repository: BudgetRepository

    init(service: BudgetService? = nil, repository: BudgetRepository? = nil) {
        self.service = service ?? BudgetService()
        self.repository = repository ?? BudgetRepository()
    }

    func replay(_ mutation: PendingMutation) async throws {
        switch mutation.operation {
        case "category_create":
            try await replayCreate(mutation)
        case "category_delete":
            try await replayDelete(mutation)
        default:
            throw MutationHandlerError.permanent("Unknown category operation '\(mutation.operation)'.")
        }
    }

    private func replayCreate(_ mutation: PendingMutation) async throws {
        let payload: CustomCategoryCreatePayload
        do {
            payload = try JSONDecoder.mutation.decode(CustomCategoryCreatePayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed category create payload: \(error.localizedDescription)")
        }

        do {
            _ = try await service.createCustomCategory(
                CreateCustomCategory(
                    homeID: payload.homeID,
                    name: payload.name,
                    emoji: payload.emoji,
                    color: payload.color
                )
            )
        } catch {
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't save category.")
        }

        try? repository.clearCategoryDirty(homeID: payload.homeID, name: payload.name)
        try? repository.clearCategoryDirty(categoryID: payload.localID)
        try? await repository.refreshCustomCategories(homeID: payload.homeID)
    }

    private func replayDelete(_ mutation: PendingMutation) async throws {
        do {
            try await service.deleteCustomCategory(id: mutation.targetID)
        } catch {
            if MutationErrorClassifier.isNotFound(error) {
                throw MutationHandlerError.reconciledByServer("Category already deleted on server.")
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't delete category.")
        }
        if let homeID = mutation.homeID {
            try? await repository.refreshCustomCategories(homeID: homeID)
        }
    }
}

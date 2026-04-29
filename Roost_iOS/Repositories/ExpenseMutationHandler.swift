import Foundation

// MARK: - ExpenseMutationHandler
//
// Replays queued expense mutations against the server when the device is
// online. Payloads are encoded by `ExpensesViewModel` via
// `OfflineAwareWrite.enqueue(_:)`; this handler decodes, calls the right
// ExpenseService method, and reconciles the cache with the server's
// authoritative response.
//
// Operations:
//   - "create"     — payload: ExpenseCreatePayload
//   - "update"     — payload: ExpenseUpdatePayload
//   - "delete"     — payload: none (expense ID lives on mutation.targetID)
//   - "settlement" — payload: ExpenseSettlementPayload (targetID = homeID)
//
// Failure classification:
//   - Network timeout / URLError / PostgrestError with 5xx → transient (retry).
//   - 4xx / decoding / auth → permanent.
//   - 409 / constraint violation → reconciledByServer (server wins).
//
// Ordering: the coordinator drains FIFO by `createdAt`. Creates enqueue with
// client-generated UUIDs, so follow-up updates/deletes targeting the same
// row replay correctly against whatever row the create resolved to.

// MARK: - Payloads

struct ExpenseCreatePayload: Codable {
    /// Carries a client-supplied UUID so cache and server agree on the PK.
    var expense: InsertExpense
    var splits: [CreateExpenseSplitPayload]
}

struct ExpenseUpdatePayload: Codable {
    var expense: Expense
    var splits: [CreateExpenseSplitPayload]
}

struct ExpenseSettlementPayload: Codable {
    var homeID: UUID
    var paidBy: UUID
    var paidTo: UUID
    var amount: Decimal
    var note: String?
    /// Expense IDs whose splits will be settled by this RPC. Used to clear
    /// the "settlement pending" flag on the local cache rows post-replay.
    var affectedExpenseIDs: [UUID]
}

/// `CreateExpenseSplit` isn't Codable because the VM-facing shape stores
/// Decimal + Date types that require a wrapper for JSON encoding.
struct CreateExpenseSplitPayload: Codable {
    var userID: UUID
    var amount: Decimal
    var settledAt: Date?
}

extension CreateExpenseSplitPayload {
    init(_ split: CreateExpenseSplit) {
        self.userID = split.userID
        self.amount = split.amount
        self.settledAt = split.settledAt
    }

    var asCreateSplit: CreateExpenseSplit {
        CreateExpenseSplit(userID: userID, amount: amount, settledAt: settledAt)
    }
}

// MARK: - Handler

@MainActor
struct ExpenseMutationHandler: MutationHandler {
    let entityType = "expense"

    private let service: ExpenseService
    private let repository: ExpenseRepository

    init(service: ExpenseService? = nil, repository: ExpenseRepository? = nil) {
        self.service = service ?? ExpenseService()
        self.repository = repository ?? ExpenseRepository()
    }

    func replay(_ mutation: PendingMutation) async throws {
        switch mutation.operation {
        case "create":
            try await replayCreate(mutation)
        case "update":
            try await replayUpdate(mutation)
        case "delete":
            try await replayDelete(mutation)
        case "settlement":
            try await replaySettlement(mutation)
        default:
            throw MutationHandlerError.permanent("Unknown expense operation '\(mutation.operation)'.")
        }
    }

    // MARK: Operations

    private func replayCreate(_ mutation: PendingMutation) async throws {
        let payload: ExpenseCreatePayload
        do {
            payload = try JSONDecoder.mutation.decode(ExpenseCreatePayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed create payload: \(error.localizedDescription)")
        }

        do {
            let splits = payload.splits.map(\.asCreateSplit)
            _ = try await service.insertExpense(payload.expense, splits: splits)
        } catch {
            throw Self.classify(error, fallback: "Couldn't create expense.")
        }

        // Post-create: clear the optimistic dirty flag so the follow-up refresh
        // can overwrite the row with authoritative server state.
        try? repository.clearDirty(expenseID: payload.expense.id)
        try? await repository.refresh(homeID: payload.expense.homeID)
    }

    private func replayUpdate(_ mutation: PendingMutation) async throws {
        let payload: ExpenseUpdatePayload
        do {
            payload = try JSONDecoder.mutation.decode(ExpenseUpdatePayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed update payload: \(error.localizedDescription)")
        }

        do {
            let splits = payload.splits.map(\.asCreateSplit)
            _ = try await service.replaceExpense(payload.expense, splits: splits)
        } catch {
            throw Self.classify(error, fallback: "Couldn't update expense.")
        }

        try? repository.clearDirty(expenseID: payload.expense.id)
        try? await repository.refresh(homeID: payload.expense.homeID)
    }

    private func replayDelete(_ mutation: PendingMutation) async throws {
        do {
            try await service.deleteExpense(id: mutation.targetID)
        } catch {
            // A 404/not-found after an offline delete is a no-op success —
            // another device already removed the row. Treat as reconciled.
            if Self.isNotFound(error) {
                throw MutationHandlerError.reconciledByServer("Already deleted on server.")
            }
            throw Self.classify(error, fallback: "Couldn't delete expense.")
        }

        if let homeID = mutation.homeID {
            try? await repository.refresh(homeID: homeID)
        }
    }

    private func replaySettlement(_ mutation: PendingMutation) async throws {
        let payload: ExpenseSettlementPayload
        do {
            payload = try JSONDecoder.mutation.decode(ExpenseSettlementPayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed settlement payload: \(error.localizedDescription)")
        }

        do {
            try await service.settleUp(
                homeID: payload.homeID,
                paidBy: payload.paidBy,
                paidTo: payload.paidTo,
                amount: payload.amount,
                note: payload.note
            )
        } catch {
            throw Self.classify(error, fallback: "Couldn't settle up.")
        }

        // Clear the "settlement pending" pseudo-dirty flags, then pull the
        // authoritative settled_at timestamps from the server.
        try? repository.clearSettlementPending(homeID: payload.homeID)
        try? await repository.refresh(homeID: payload.homeID)
    }

    // MARK: Error classification

    private static func classify(_ error: Error, fallback: String) -> MutationHandlerError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost:
                return .transient(urlError.localizedDescription)
            default:
                return .transient(urlError.localizedDescription)
            }
        }

        let description = String(describing: error)
        // Supabase PostgrestError surfaces as a struct with a `.code` and
        // `.message`; checking the description is a safe, SDK-version-
        // resilient classification until we promote to a typed case.
        let lower = description.lowercased()
        if lower.contains("401") || lower.contains("unauthorized") || lower.contains("jwt") {
            return .authExpired
        }
        if lower.contains("409") || lower.contains("conflict") {
            return .reconciledByServer(description)
        }
        if lower.contains("4") && (lower.contains("400") || lower.contains("403") || lower.contains("404") || lower.contains("422")) {
            return .permanent(description)
        }
        // Default to transient — safer to retry than to give up silently.
        _ = fallback
        return .transient(description)
    }

    private static func isNotFound(_ error: Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("404") || description.contains("not found") || description.contains("no rows")
    }
}

// NOTE: JSONEncoder.mutation / JSONDecoder.mutation moved to
// `Shared/MutationCoding.swift` so they can be used from the RoostWidgets
// extension as well.

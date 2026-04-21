import Foundation

// MARK: - ShoppingMutationHandler
//
// Replays queued shopping-list mutations against the server.
//
// Operations:
//   - "create" — payload `ShoppingCreatePayload` wraps an `InsertShoppingItem`
//   - "update" — payload is the full `ShoppingItem` (LWW on the server)
//   - "delete" — no payload, uses `mutation.targetID`

struct ShoppingCreatePayload: Codable {
    var item: InsertShoppingItem
}

@MainActor
struct ShoppingMutationHandler: MutationHandler {
    let entityType = "shopping_item"

    private let service: ShoppingService
    private let repository: ShoppingRepository

    init(service: ShoppingService = ShoppingService(), repository: ShoppingRepository? = nil) {
        self.service = service
        self.repository = repository ?? ShoppingRepository()
    }

    func replay(_ mutation: PendingMutation) async throws {
        switch mutation.operation {
        case "create":   try await replayCreate(mutation)
        case "update":   try await replayUpdate(mutation)
        case "delete":   try await replayDelete(mutation)
        default:
            throw MutationHandlerError.permanent("Unknown shopping operation '\(mutation.operation)'.")
        }
    }

    private func replayCreate(_ mutation: PendingMutation) async throws {
        let payload: ShoppingCreatePayload
        do {
            payload = try JSONDecoder.mutation.decode(ShoppingCreatePayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed shopping create payload: \(error.localizedDescription)")
        }

        do {
            try await service.insertItem(payload.item)
            try repository.clearDirty(itemID: payload.item.id)
        } catch {
            // Duplicate-key races (server already has this row via another
            // device) are treated as LWW wins — the row is live on the
            // server; the next refresh will reconcile attributes.
            if MutationErrorClassifier.isDuplicate(error) {
                try repository.clearDirty(itemID: payload.item.id)
                throw MutationHandlerError.reconciledByServer("Shopping item already existed on server.")
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't save shopping item.")
        }
    }

    private func replayUpdate(_ mutation: PendingMutation) async throws {
        let item: ShoppingItem
        do {
            item = try JSONDecoder.mutation.decode(ShoppingItem.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed shopping update payload: \(error.localizedDescription)")
        }

        do {
            try await service.updateItem(item)
            try repository.clearDirty(itemID: item.id)
        } catch {
            if MutationErrorClassifier.isNotFound(error) {
                // Row was deleted server-side — not a failure; just drop the
                // local dirty marker. The next refresh will remove the row.
                try repository.clearDirty(itemID: item.id)
                throw MutationHandlerError.reconciledByServer("Shopping item was already removed on the server.")
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't update shopping item.")
        }
    }

    private func replayDelete(_ mutation: PendingMutation) async throws {
        let itemID = mutation.targetID
        do {
            try await service.deleteItem(id: itemID)
        } catch {
            if MutationErrorClassifier.isNotFound(error) {
                // Already gone — idempotent success.
                return
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't delete shopping item.")
        }
    }
}

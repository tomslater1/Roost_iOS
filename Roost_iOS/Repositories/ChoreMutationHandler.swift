import Foundation

// MARK: - ChoreMutationHandler
//
// Replays queued chore mutations against the server.
//
// Operations:
//   - "create" — payload `ChoreCreatePayload` wraps an `InsertChore`
//   - "update" — payload is the full `Chore` (LWW on the server)
//   - "delete" — no payload, uses `mutation.targetID`

struct ChoreCreatePayload: Codable {
    var chore: InsertChore
}

@MainActor
struct ChoreMutationHandler: MutationHandler {
    let entityType = "chore"

    private let service: ChoreService
    private let repository: ChoreRepository

    init(service: ChoreService = ChoreService(), repository: ChoreRepository? = nil) {
        self.service = service
        self.repository = repository ?? ChoreRepository()
    }

    func replay(_ mutation: PendingMutation) async throws {
        switch mutation.operation {
        case "create":   try await replayCreate(mutation)
        case "update":   try await replayUpdate(mutation)
        case "delete":   try await replayDelete(mutation)
        default:
            throw MutationHandlerError.permanent("Unknown chore operation '\(mutation.operation)'.")
        }
    }

    private func replayCreate(_ mutation: PendingMutation) async throws {
        let payload: ChoreCreatePayload
        do {
            payload = try JSONDecoder.mutation.decode(ChoreCreatePayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed chore create payload: \(error.localizedDescription)")
        }

        do {
            try await service.insertChore(payload.chore)
            try repository.clearDirty(choreID: payload.chore.id)
        } catch {
            if MutationErrorClassifier.isDuplicate(error) {
                try repository.clearDirty(choreID: payload.chore.id)
                throw MutationHandlerError.reconciledByServer("Chore already existed on server.")
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't save chore.")
        }
    }

    private func replayUpdate(_ mutation: PendingMutation) async throws {
        let chore: Chore
        do {
            chore = try JSONDecoder.mutation.decode(Chore.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed chore update payload: \(error.localizedDescription)")
        }

        do {
            try await service.updateChore(chore)
            try repository.clearDirty(choreID: chore.id)
        } catch {
            if MutationErrorClassifier.isNotFound(error) {
                try repository.clearDirty(choreID: chore.id)
                throw MutationHandlerError.reconciledByServer("Chore was already removed on the server.")
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't update chore.")
        }
    }

    private func replayDelete(_ mutation: PendingMutation) async throws {
        let choreID = mutation.targetID
        do {
            try await service.deleteChore(id: choreID)
        } catch {
            if MutationErrorClassifier.isNotFound(error) {
                return
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't delete chore.")
        }
    }
}

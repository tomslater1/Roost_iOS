import Foundation

// MARK: - SavingsGoalMutationHandler
//
// Replays queued savings goal mutations against the server.
//
// Operations:
//   - "create"           — payload SavingsGoalCreatePayload (carries client UUID)
//   - "delete"           — no payload (targetID = goal.id)
//   - "complete"         — no payload (targetID = goal.id)
//   - "add_contribution" — payload SavingsGoalContributionPayload (delta amount)
//
// LWW on the savedAmount: the server's authoritative state lands via the
// post-replay refresh. If two devices added contributions offline, their
// deltas are additive on the server side (we replay with the recorded delta,
// not an absolute value), so neither one clobbers the other.

// MARK: - Payloads

struct SavingsGoalCreatePayload: Codable {
    var goal: InsertSavingsGoal
}

struct SavingsGoalContributionPayload: Codable {
    var goalID: UUID
    var delta: Decimal
    var homeID: UUID
}

// MARK: - Handler

@MainActor
struct SavingsGoalMutationHandler: MutationHandler {
    let entityType = "savings_goal"

    private let service: SavingsGoalsService
    private let repository: SavingsGoalRepository

    init(service: SavingsGoalsService? = nil, repository: SavingsGoalRepository? = nil) {
        self.service = service ?? SavingsGoalsService()
        self.repository = repository ?? SavingsGoalRepository()
    }

    func replay(_ mutation: PendingMutation) async throws {
        switch mutation.operation {
        case "create":
            try await replayCreate(mutation)
        case "delete":
            try await replayDelete(mutation)
        case "complete":
            try await replayComplete(mutation)
        case "add_contribution":
            try await replayAddContribution(mutation)
        default:
            throw MutationHandlerError.permanent("Unknown savings goal operation '\(mutation.operation)'.")
        }
    }

    private func replayCreate(_ mutation: PendingMutation) async throws {
        let payload: SavingsGoalCreatePayload
        do {
            payload = try JSONDecoder.mutation.decode(SavingsGoalCreatePayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed savings goal create payload: \(error.localizedDescription)")
        }

        do {
            _ = try await service.insertGoal(payload.goal)
        } catch {
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't create savings goal.")
        }

        try? repository.clearDirty(goalID: payload.goal.id)
        try? await repository.refresh(homeID: payload.goal.homeId)
    }

    private func replayDelete(_ mutation: PendingMutation) async throws {
        do {
            try await service.deleteGoal(id: mutation.targetID)
        } catch {
            if MutationErrorClassifier.isNotFound(error) {
                throw MutationHandlerError.reconciledByServer("Goal already deleted on server.")
            }
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't delete goal.")
        }

        if let homeID = mutation.homeID {
            try? await repository.refresh(homeID: homeID)
        }
    }

    private func replayComplete(_ mutation: PendingMutation) async throws {
        do {
            _ = try await service.completeGoal(id: mutation.targetID)
        } catch {
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't mark goal complete.")
        }

        try? repository.clearDirty(goalID: mutation.targetID)
        if let homeID = mutation.homeID {
            try? await repository.refresh(homeID: homeID)
        }
    }

    private func replayAddContribution(_ mutation: PendingMutation) async throws {
        let payload: SavingsGoalContributionPayload
        do {
            payload = try JSONDecoder.mutation.decode(SavingsGoalContributionPayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed contribution payload: \(error.localizedDescription)")
        }

        do {
            _ = try await service.addToGoal(id: payload.goalID, amount: payload.delta)
        } catch {
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't add contribution.")
        }

        try? repository.clearDirty(goalID: payload.goalID)
        try? await repository.refresh(homeID: payload.homeID)
    }
}

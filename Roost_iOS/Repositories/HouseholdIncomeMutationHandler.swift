import Foundation

// MARK: - HouseholdIncomeMutationHandler
//
// Replays queued household-income mutations against the server.
//
// Operations:
//   - "set_my_income"   — payload HouseholdIncomeSetMyIncomePayload
//                         (updates home_members.personal_income and then
//                         re-syncs the derived household_income row)
//   - "set_visibility"  — payload HouseholdIncomeSetVisibilityPayload
//                         (updates home_members.income_visible_to_partner)
//
// LWW: personal_income is a scalar per member; the server row the user owns
// is keyed by their own `user_id`, so two devices editing it race but never
// stomp on their partner's data. Last-to-reconnect wins for the same user,
// which matches the rest of the offline story.

// MARK: - Payloads

struct HouseholdIncomeSetMyIncomePayload: Codable {
    var userID: UUID
    var amount: Decimal
    var homeID: UUID
    var month: Date
}

struct HouseholdIncomeSetVisibilityPayload: Codable {
    var userID: UUID
    var visible: Bool
    var homeID: UUID
}

// MARK: - Handler

@MainActor
struct HouseholdIncomeMutationHandler: MutationHandler {
    let entityType = "household_income"

    private let service: HouseholdIncomeService

    init(service: HouseholdIncomeService? = nil) {
        self.service = service ?? HouseholdIncomeService()
    }

    func replay(_ mutation: PendingMutation) async throws {
        switch mutation.operation {
        case "set_my_income":
            try await replaySetMyIncome(mutation)
        case "set_visibility":
            try await replaySetVisibility(mutation)
        default:
            throw MutationHandlerError.permanent("Unknown household income operation '\(mutation.operation)'.")
        }
    }

    private func replaySetMyIncome(_ mutation: PendingMutation) async throws {
        let payload: HouseholdIncomeSetMyIncomePayload
        do {
            payload = try JSONDecoder.mutation.decode(HouseholdIncomeSetMyIncomePayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed household income payload: \(error.localizedDescription)")
        }

        do {
            try await service.setMyIncome(userId: payload.userID, amount: payload.amount)
            try await service.syncCombinedIncome(homeId: payload.homeID, month: payload.month)
        } catch {
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't save income.")
        }
    }

    private func replaySetVisibility(_ mutation: PendingMutation) async throws {
        let payload: HouseholdIncomeSetVisibilityPayload
        do {
            payload = try JSONDecoder.mutation.decode(HouseholdIncomeSetVisibilityPayload.self, from: mutation.payloadData)
        } catch {
            throw MutationHandlerError.permanent("Malformed income visibility payload: \(error.localizedDescription)")
        }

        do {
            try await service.setIncomeVisibility(userId: payload.userID, visible: payload.visible)
        } catch {
            throw MutationErrorClassifier.classify(error, fallback: "Couldn't update income visibility.")
        }
    }
}

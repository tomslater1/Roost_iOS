import Foundation
import Observation
import Realtime

@MainActor
@Observable
final class HomeManager {
    var home: Home?
    var members: [HomeMember] = []
    var isLoading = false
    var errorMessage: String?

    private(set) var currentUserId: UUID?

    @ObservationIgnored
    private let homeService = HomeService()

    @ObservationIgnored
    private var homeSubscriptionId: UUID?

    @ObservationIgnored
    private var memberSubscriptionId: UUID?

    @ObservationIgnored
    private var subscribedHomeId: UUID?

    var currentMember: HomeMember? {
        guard let currentUserId else { return nil }
        return members.first { $0.userID == currentUserId }
    }

    var partner: HomeMember? {
        guard let currentUserId else { return nil }
        return members.first { $0.userID != currentUserId }
    }

    var homeId: UUID? { home?.id }

    func loadHome(homeId: UUID, userId: UUID) async {
        currentUserId = userId
        isLoading = true
        errorMessage = nil

        do {
            async let homeResult = homeService.fetchHome(id: homeId)
            async let membersResult = homeService.fetchMembers(homeId: homeId)

            home = try await homeResult
            members = try await membersResult
        } catch {
            errorMessage = String(describing: error)
        }

        isLoading = false
    }

    func refreshCurrentHome() async {
        guard let homeId = home?.id ?? subscribedHomeId,
              let currentUserId else { return }
        await loadHome(homeId: homeId, userId: currentUserId)
    }

    func startRealtime(homeId: UUID, userId: UUID) async {
        if let subscribedHomeId, subscribedHomeId != homeId {
            await stopRealtime()
        }

        currentUserId = userId
        guard homeSubscriptionId == nil, memberSubscriptionId == nil else { return }
        subscribedHomeId = homeId

        homeSubscriptionId = await RealtimeManager.shared.subscribe(
            table: "homes",
            filter: .eq("id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self else { return }
            await self.refreshCurrentHome()
        }

        memberSubscriptionId = await RealtimeManager.shared.subscribe(
            table: "home_members",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self else { return }
            await self.refreshCurrentHome()
        }
    }

    func stopRealtime() async {
        if let homeSubscriptionId {
            await RealtimeManager.shared.unsubscribe(table: "homes", callbackId: homeSubscriptionId)
            self.homeSubscriptionId = nil
        }
        if let memberSubscriptionId {
            await RealtimeManager.shared.unsubscribe(table: "home_members", callbackId: memberSubscriptionId)
            self.memberSubscriptionId = nil
        }
        subscribedHomeId = nil
    }

    func clearHomeState() {
        home = nil
        members = []
        errorMessage = nil
    }

    // MARK: - Optimistic patching
    //
    // Local, in-memory patches applied while a matching mutation is queued
    // in the outbox. A follow-up `refreshCurrentHome()` (or realtime fire)
    // reconciles with authoritative server state.

    /// Patches `personalIncome` and `incomeSetAt` on the member matching `userID`.
    func patchMemberIncome(userID: UUID, amount: Decimal) {
        guard let idx = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[idx].personalIncome = amount
        members[idx].incomeSetAt = Date()
    }

    /// Patches `incomeVisibleToPartner` on the member matching `userID`.
    func patchMemberIncomeVisibility(userID: UUID, visible: Bool) {
        guard let idx = members.firstIndex(where: { $0.userID == userID }) else { return }
        members[idx].incomeVisibleToPartner = visible
    }

    static func previewDashboard() -> HomeManager {
        let manager = HomeManager()
        let homeId = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
        let userId = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
        let partnerId = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()

        manager.home = Home(
            id: homeId,
            name: "Rose Cottage",
            inviteCode: "ROOST7",
            nextShopDate: "2026-04-02",
            subscriptionStatus: "trialing",
            subscriptionTier: "nest",
            trialEndsAt: Calendar.current.date(byAdding: .day, value: 10, to: .now),
            currentPeriodEndsAt: nil,
            stripeCustomerID: "cus_preview",
            stripeSubscriptionID: "sub_preview",
            stripePriceID: "price_preview_monthly",
            hasUsedTrial: false,
            createdAt: .now
        )
        manager.members = [
            HomeMember(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
                homeID: homeId,
                userID: userId,
                displayName: "Tom",
                avatarColor: "terracotta",
                avatarIcon: "home",
                role: "owner",
                joinedAt: .now
            ),
            HomeMember(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
                homeID: homeId,
                userID: partnerId,
                displayName: "Jess",
                avatarColor: "sage",
                avatarIcon: "leaf",
                role: "member",
                joinedAt: .now
            )
        ]
        manager.currentUserId = userId
        return manager
    }
}

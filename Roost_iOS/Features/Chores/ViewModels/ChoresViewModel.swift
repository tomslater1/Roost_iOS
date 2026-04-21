import Foundation
import Observation
import Realtime

@MainActor
@Observable
final class ChoresViewModel {
    var chores: [Chore] = []
    var rooms: [Room] = []
    var roomGroups: [RoomGroup] = []
    var completionHistoryByChoreId: [UUID: [ActivityFeedItem]] = [:]
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored
    private let choreService = ChoreService()

    @ObservationIgnored
    private let choreRepository = ChoreRepository()

    @ObservationIgnored
    private let hazelService = HazelService()

    @ObservationIgnored
    private let roomService = RoomService()

    @ObservationIgnored
    private let activityService = ActivityService()

    @ObservationIgnored
    private var choreSubscriptionId: UUID?

    @ObservationIgnored
    private var activitySubscriptionId: UUID?

    @ObservationIgnored
    private var subscribedHomeId: UUID?

    init(
        chores: [Chore] = [],
        rooms: [Room] = [],
        roomGroups: [RoomGroup] = [],
        completionHistoryByChoreId: [UUID: [ActivityFeedItem]] = [:],
        isLoading: Bool = false,
        errorMessage: String? = nil
    ) {
        self.chores = chores
        self.rooms = rooms
        self.roomGroups = roomGroups
        self.completionHistoryByChoreId = completionHistoryByChoreId
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    var sortedChores: [Chore] {
        chores.sorted { lhs, rhs in
            let lhsRank = sortRank(for: lhs)
            let rhsRank = sortRank(for: rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    func load(homeId: UUID) async {
        isLoading = true
        errorMessage = nil

        // Cache-first paint so the chores list renders instantly offline.
        if let cached = try? choreRepository.loadCached(homeID: homeId) {
            chores = cached
        }

        do {
            async let choresResult = choreRepository.refresh(homeID: homeId)
            async let roomsResult = roomService.fetchRooms(for: homeId)
            async let roomGroupsResult = roomService.fetchRoomGroups(for: homeId)
            async let activityResult = activityService.fetchActivity(for: homeId)

            try await choresResult
            if let refreshed = try? choreRepository.loadCached(homeID: homeId) {
                chores = refreshed
            }
            rooms = try await roomsResult
            roomGroups = try await roomGroupsResult
            completionHistoryByChoreId = groupedCompletionHistory(from: try await activityResult)
        } catch {
            if !isCancellation(error) && !isNetworkFailure(error) {
                errorMessage = String(describing: error)
            }
        }

        isLoading = false
    }

    func addChore(
        title: String,
        description: String?,
        assignedTo: UUID?,
        frequency: String,
        dueDate: Date?,
        room: String?,
        homeId: UUID,
        userId: UUID,
        hazelEnabled: Bool = false
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        var resolvedTitle = trimmedTitle
        if hazelEnabled {
            if let result = await hazelService.normalizeChoreTitle(text: trimmedTitle, homeId: homeId) {
                resolvedTitle = result.text
            }
        }

        let newID = UUID()
        let now = Date()
        let optimistic = Chore(
            id: newID,
            homeID: homeId,
            title: resolvedTitle,
            description: normalized(description),
            room: normalized(room),
            assignedTo: assignedTo,
            dueDate: dueDate,
            completedBy: nil,
            frequency: frequency,
            lastCompletedAt: nil,
            createdAt: now
        )

        do {
            try choreRepository.applyOptimisticUpsert(optimistic, pendingOperation: "create")
            chores.append(optimistic)

            let insert = InsertChore(
                id: newID,
                homeID: homeId,
                title: resolvedTitle,
                description: normalized(description),
                room: normalized(room),
                assignedTo: assignedTo,
                dueDate: dueDate,
                frequency: frequency,
                createdAt: now
            )
            let payload = try JSONEncoder.mutation.encode(ChoreCreatePayload(chore: insert))
            try OfflineAwareWrite.enqueue(.init(
                entityType: "chore",
                operation: "create",
                targetID: newID,
                homeID: homeId,
                payload: payload
            ))

            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: userId.uuidString,
                action: "added chore \(resolvedTitle)",
                entityType: "chore",
                entityId: newID.uuidString
            )
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleCompletion(_ chore: Chore, currentUserId: UUID, homeId: UUID) async {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else { return }

        let original = chores[index]
        var updated = original

        if original.isCompleted {
            updated.completedBy = nil
            updated.lastCompletedAt = nil
        } else {
            let completionDate = Date()
            updated.completedBy = currentUserId
            updated.lastCompletedAt = completionDate
            updated.dueDate = nextDueDate(from: original.dueDate, frequency: original.frequency, completionDate: completionDate)
        }

        do {
            try choreRepository.applyOptimisticUpsert(updated, pendingOperation: "update")
            chores[index] = updated

            let payload = try JSONEncoder.mutation.encode(updated)
            try OfflineAwareWrite.enqueue(.init(
                entityType: "chore",
                operation: "update",
                targetID: updated.id,
                homeID: homeId,
                payload: payload
            ))

            if updated.isCompleted {
                ActivityService.logActivity(
                    homeId: homeId.uuidString,
                    userId: currentUserId.uuidString,
                    action: "completed \(updated.title)",
                    entityType: "chore",
                    entityId: updated.id.uuidString
                )
                await refreshCompletionHistory(homeId: homeId)
            } else {
                ActivityService.logActivity(
                    homeId: homeId.uuidString,
                    userId: currentUserId.uuidString,
                    action: "uncompleted \(updated.title)",
                    entityType: "chore",
                    entityId: updated.id.uuidString
                )
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func deleteChore(_ chore: Chore, homeId: UUID, userId: UUID) async {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else { return }
        let removed = chores.remove(at: index)

        do {
            try choreRepository.applyOptimisticDelete(choreID: removed.id)
            try OfflineAwareWrite.enqueue(.init(
                entityType: "chore",
                operation: "delete",
                targetID: removed.id,
                homeID: homeId,
                payload: Data()
            ))

            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: userId.uuidString,
                action: "deleted chore \(removed.title)",
                entityType: "chore",
                entityId: removed.id.uuidString
            )
        } catch {
            chores.insert(removed, at: min(index, chores.count))
            errorMessage = String(describing: error)
        }
    }

    func completionHistory(for choreId: UUID) -> [ActivityFeedItem] {
        completionHistoryByChoreId[choreId] ?? []
    }

    func streak(for chore: Chore) -> Int {
        guard chore.isRecurring, let frequency = chore.frequency else { return 0 }

        let history = completionHistory(for: chore.id)
        guard !history.isEmpty else { return 0 }

        let calendar = Calendar.current
        let orderedDates = history
            .map(\.createdAt)
            .sorted(by: >)

        var streak = 1

        for pair in zip(orderedDates, orderedDates.dropFirst()) {
            let current = pair.0
            let previous = pair.1

            let matchesExpectedGap: Bool
            switch frequency {
            case "daily":
                matchesExpectedGap = calendar.isDate(previous, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: current) ?? current)
            case "weekly":
                let weekOfCurrent = calendar.dateInterval(of: .weekOfYear, for: current)?.start
                let weekOfPrevious = calendar.dateInterval(of: .weekOfYear, for: previous)?.start
                if let weekOfCurrent, let expectedPrevious = calendar.date(byAdding: .weekOfYear, value: -1, to: weekOfCurrent) {
                    matchesExpectedGap = weekOfPrevious == expectedPrevious
                } else {
                    matchesExpectedGap = false
                }
            case "monthly":
                let previousMonth = calendar.dateComponents([.year, .month], from: previous)
                if let expectedPrevious = calendar.date(byAdding: .month, value: -1, to: current) {
                    matchesExpectedGap = previousMonth.year == calendar.component(.year, from: expectedPrevious)
                        && previousMonth.month == calendar.component(.month, from: expectedPrevious)
                } else {
                    matchesExpectedGap = false
                }
            default:
                matchesExpectedGap = false
            }

            if matchesExpectedGap {
                streak += 1
            } else {
                break
            }
        }

        return streak
    }

    func suggestChores(homeId: UUID) async -> [String] {
        let existingTitles = chores.map(\.title)
        let monthLabel = Date().formatted(.dateTime.month(.wide).year())
        return await hazelService.suggestChores(
            existingChores: existingTitles,
            month: monthLabel,
            homeId: homeId
        )
    }

    func startRealtime(homeId: UUID) async {
        if let subscribedHomeId, subscribedHomeId != homeId {
            await stopRealtime()
        }
        guard choreSubscriptionId == nil, activitySubscriptionId == nil else { return }
        subscribedHomeId = homeId

        choreSubscriptionId = await RealtimeManager.shared.subscribe(
            table: "chores",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self, let homeId = self.subscribedHomeId else { return }
            await self.refreshChores(homeId: homeId)
        }

        activitySubscriptionId = await RealtimeManager.shared.subscribe(
            table: "activity_feed",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self, let homeId = self.subscribedHomeId else { return }
            await self.refreshCompletionHistory(homeId: homeId)
        }
    }

    func stopRealtime() async {
        if let choreSubscriptionId {
            await RealtimeManager.shared.unsubscribe(table: "chores", callbackId: choreSubscriptionId)
            self.choreSubscriptionId = nil
        }

        if let activitySubscriptionId {
            await RealtimeManager.shared.unsubscribe(table: "activity_feed", callbackId: activitySubscriptionId)
            self.activitySubscriptionId = nil
        }

        subscribedHomeId = nil
    }

    private func refreshChores(homeId: UUID) async {
        do {
            try await choreRepository.refresh(homeID: homeId)
            if let refreshed = try? choreRepository.loadCached(homeID: homeId) {
                chores = refreshed
            }
        } catch {
            if !isCancellation(error) && !isNetworkFailure(error) {
                errorMessage = String(describing: error)
            }
        }
    }

    private func refreshCompletionHistory(homeId: UUID) async {
        do {
            let activity = try await activityService.fetchActivity(for: homeId)
            completionHistoryByChoreId = groupedCompletionHistory(from: activity)
        } catch {
            if !isCancellation(error) {
                errorMessage = String(describing: error)
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled ||
        (error as NSError).code == NSURLErrorCancelled
    }

    private func isNetworkFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func groupedCompletionHistory(from activity: [ActivityFeedItem]) -> [UUID: [ActivityFeedItem]] {
        Dictionary(grouping: activity.filter { item in
            item.entityType == "chore"
                && item.entityID != nil
                && item.action.localizedLowercase.hasPrefix("completed")
        }) { $0.entityID! }
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func sortRank(for chore: Chore) -> Int {
        if chore.isCompleted { return 2 }
        if chore.isOverdue { return 0 }
        return 1
    }

    private func nextDueDate(from dueDate: Date?, frequency: String?, completionDate: Date) -> Date? {
        guard let frequency else { return dueDate }

        let calendar = Calendar.current
        let baseDate = dueDate ?? completionDate

        switch frequency {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: baseDate)
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: 1, to: baseDate)
        case "monthly":
            return calendar.date(byAdding: .month, value: 1, to: baseDate)
        default:
            return dueDate
        }
    }
}

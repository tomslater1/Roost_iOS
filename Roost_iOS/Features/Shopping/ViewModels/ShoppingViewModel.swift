import Foundation
import Observation
import Realtime
import WidgetKit

// MARK: - Offline-aware Shopping (Phase 3)
//
// Reads are cache-first via `ShoppingRepository`; writes go through
// `OfflineAwareWrite.enqueue`, which:
//
//   1. Applies an optimistic cache write (sets isDirty = true +
//      pendingOperation).
//   2. Enqueues a `PendingMutation` for the real server call.
//   3. Triggers `SyncCoordinator.drainIfOnline()` so the replay runs
//      immediately when online (and is a no-op when offline).
//
// The old direct-service rollback pattern is gone — the queue owns
// retry/failure. If a mutation ultimately fails permanently, it surfaces
// in Settings → Pending Changes rather than silently rolling back here.

@MainActor
@Observable
final class ShoppingViewModel {
    var items: [ShoppingItem] = []
    var isLoading = false
    var errorMessage: String?

    init() {}

    init(items: [ShoppingItem], isLoading: Bool = false, errorMessage: String? = nil) {
        self.items = items
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    /// Items grouped by category for section display. Uncategorised items go under "Other".
    var groupedItems: [(category: String, items: [ShoppingItem])] {
        let grouped = Dictionary(grouping: items) { item in
            (item.category?.isEmpty == false) ? item.category! : "Other"
        }
        return grouped
            .sorted { $0.key == "Other" ? true : ($1.key == "Other" ? false : $0.key < $1.key) }
            .map { (category: $0.key, items: $0.value) }
    }

    @ObservationIgnored
    private let repository = ShoppingRepository()

    @ObservationIgnored
    private let hazelService = HazelService()

    @ObservationIgnored
    private var realtimeSubscriptionId: UUID?

    @ObservationIgnored
    private var subscribedHomeId: UUID?

    func loadItems(homeId: UUID) async {
        isLoading = true
        errorMessage = nil

        // 1) Cache-first — instant paint.
        if let cached = try? repository.loadCached(homeID: homeId) {
            items = cached
        }

        // 2) Refresh from server in the background; swallow network errors so
        //    offline users keep their cached list.
        do {
            try await repository.refresh(homeID: homeId)
            if let refreshed = try? repository.loadCached(homeID: homeId) {
                items = refreshed
            }
        } catch {
            if !isCancellation(error) && !isNetworkFailure(error) {
                errorMessage = String(describing: error)
            }
        }

        isLoading = false
    }

    func addItem(
        name: String,
        quantity: String?,
        category: String?,
        homeId: UUID,
        userId: UUID,
        hazelEnabled: Bool = false
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // If Hazel is enabled and no category was manually provided, normalize
        // and auto-categorize. Hazel requires network, so when offline we just
        // fall through with the raw name + no category; the row stays
        // uncategorised until the user edits it online (Phase 3 doesn't yet
        // defer Hazel normalisation like it does expense categorisation).
        var resolvedName = trimmedName
        var resolvedCategory = category?.isEmpty == true ? nil : category

        if hazelEnabled, resolvedCategory == nil {
            if let result = await hazelService.normalizeShoppingItem(text: trimmedName, homeId: homeId) {
                resolvedName = result.text
                resolvedCategory = result.category
            }
        }

        let resolvedQuantity: String? = quantity?.isEmpty == true ? nil : quantity
        let newID = UUID()
        let now = Date()

        let optimistic = ShoppingItem(
            id: newID,
            homeID: homeId,
            name: resolvedName,
            quantity: resolvedQuantity,
            category: resolvedCategory,
            checked: false,
            addedBy: userId,
            checkedBy: nil,
            createdAt: now,
            updatedAt: nil
        )

        do {
            try repository.applyOptimisticUpsert(optimistic, pendingOperation: "create")
            if let cached = try? repository.loadCached(homeID: homeId) {
                items = cached
            } else {
                items.insert(optimistic, at: 0)
            }

            let insert = InsertShoppingItem(
                id: newID,
                homeID: homeId,
                name: resolvedName,
                quantity: resolvedQuantity,
                category: resolvedCategory,
                checked: false
            )
            let payload = try JSONEncoder.mutation.encode(ShoppingCreatePayload(item: insert))
            try OfflineAwareWrite.enqueue(.init(
                entityType: "shopping_item",
                operation: "create",
                targetID: newID,
                homeID: homeId,
                payload: payload
            ))

            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: userId.uuidString,
                action: "added \(trimmedName) to the shopping list",
                entityType: "shopping_item",
                entityId: newID.uuidString
            )
            notifyExternalSurfaces()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleItem(_ item: ShoppingItem, homeId: UUID, userId: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        var updated = items[index]
        updated.checked.toggle()
        updated.checkedBy = updated.checked ? userId : nil
        updated.updatedAt = Date()
        let nowCompleted = updated.checked

        do {
            try repository.applyOptimisticUpsert(updated, pendingOperation: "update")
            items[index] = updated

            let payload = try JSONEncoder.mutation.encode(updated)
            try OfflineAwareWrite.enqueue(.init(
                entityType: "shopping_item",
                operation: "update",
                targetID: updated.id,
                homeID: homeId,
                payload: payload
            ))

            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: userId.uuidString,
                action: nowCompleted
                    ? "checked off \(item.name)"
                    : "unchecked \(item.name)",
                entityType: "shopping_item",
                entityId: item.id.uuidString
            )
            notifyExternalSurfaces()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteItem(_ item: ShoppingItem, homeId: UUID, userId: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)

        do {
            try repository.applyOptimisticDelete(itemID: removed.id)
            try OfflineAwareWrite.enqueue(.init(
                entityType: "shopping_item",
                operation: "delete",
                targetID: removed.id,
                homeID: homeId,
                payload: Data()
            ))

            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: userId.uuidString,
                action: "removed \(removed.name) from the shopping list",
                entityType: "shopping_item",
                entityId: removed.id.uuidString
            )
            notifyExternalSurfaces()
        } catch {
            // Restore if enqueue itself failed (rare — SwiftData full).
            items.insert(removed, at: min(index, items.count))
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Realtime

    func startRealtime(homeId: UUID) async {
        if let subscribedHomeId, subscribedHomeId != homeId {
            await stopRealtime()
        }
        guard realtimeSubscriptionId == nil else { return }
        subscribedHomeId = homeId

        realtimeSubscriptionId = await RealtimeManager.shared.subscribe(
            table: "shopping_items",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self, let homeId = self.subscribedHomeId else { return }
            await self.loadItems(homeId: homeId)
            self.notifyExternalSurfaces()
        }
    }

    func stopRealtime() async {
        guard let subId = realtimeSubscriptionId else { return }
        await RealtimeManager.shared.unsubscribe(table: "shopping_items", callbackId: subId)
        realtimeSubscriptionId = nil
        subscribedHomeId = nil
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled ||
        (error as NSError).code == NSURLErrorCancelled
    }

    /// Called after any local shopping-list write so widgets + the live
    /// activity reflect the latest state.
    private func notifyExternalSurfaces() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ShoppingWidget")
        ShoppingTripManager.shared.refreshActiveActivity()
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
}

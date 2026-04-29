//
//  ToggleShoppingItemIntent.swift
//  RoostWidgets
//
//  Executes when the user taps a check circle in the Shopping widget or
//  the Shopping Trip Live Activity. Runs in the widget extension's
//  process, writes directly to the shared SwiftData store, enqueues a
//  PendingMutation for the main app's SyncCoordinator to drain on next
//  launch, then reloads widget timelines.
//
//  Does NOT call `OfflineAwareWrite.enqueue` because that triggers
//  `SyncCoordinator.drainIfOnline()` which depends on main-app-only
//  services (Supabase, realtime). We talk to the MutationQueue directly.
//

import ActivityKit
import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct ToggleShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Shopping Item"
    static var description = IntentDescription("Toggle a shopping list item on or off.")

    /// We handle everything in the background — no need to launch the app.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item ID")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: itemID) else {
            return .result()
        }

        do {
            let container = try SharedShoppingReader.sharedModelContainer()
            let context = ModelContext(container)

            let descriptor = FetchDescriptor<CachedShoppingItem>(
                predicate: #Predicate { $0.id == uuid }
            )
            guard let cached = try context.fetch(descriptor).first else {
                return .result()
            }

            // Optimistic flip against the shared cache.
            let newChecked = !cached.checked
            cached.checked = newChecked
            cached.isDirty = true
            cached.pendingOperation = "update"

            // Build the full ShoppingItem payload the main app's
            // ShoppingMutationHandler expects for an "update" mutation.
            let currentUserID = AppGroup.Context.currentUserID
            let shoppingItem = ShoppingItem(
                id: cached.id,
                homeID: cached.homeID,
                name: cached.name,
                quantity: cached.quantity,
                category: cached.category,
                checked: newChecked,
                addedBy: nil,            // Cache doesn't retain addedBy;
                                         // matches the main-app ViewModel path.
                checkedBy: newChecked ? currentUserID : nil,
                createdAt: cached.createdAt,
                updatedAt: Date()
            )

            let payloadData = (try? JSONEncoder.mutation.encode(shoppingItem)) ?? Data()

            let mutation = PendingMutation(
                entityType: "shopping_item",
                operation: "update",
                targetID: cached.id,
                homeID: cached.homeID,
                payloadData: payloadData,
                clientTimestamp: Date(),
                deviceID: DeviceIdentity.current
            )
            context.insert(mutation)
            try context.save()
        } catch {
            // Swallow — the widget tap must feel instant. Main app reconciles on next launch.
        }

        // Refresh all widgets of this kind (small/medium/large/lock screen).
        WidgetCenter.shared.reloadTimelines(ofKind: "ShoppingWidget")

        // If a Shopping Trip Live Activity is running, update its ContentState
        // so the progress ring + preview items reflect the new check state.
        if #available(iOS 17.0, *) {
            if let activity = Activity<ShoppingTripAttributes>.activities.first {
                let newState = SharedShoppingReader.currentTripState()
                await activity.update(
                    ActivityContent(state: newState, staleDate: nil)
                )
            }
        }

        return .result()
    }
}

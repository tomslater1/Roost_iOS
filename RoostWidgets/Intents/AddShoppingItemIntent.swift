//
//  AddShoppingItemIntent.swift
//  RoostWidgets
//
//  "Hey Siri, add milk to shopping list" / Shortcuts action / Action Button.
//  Parses one or more comma-/and-separated items and inserts them into
//  the shared SwiftData store, enqueueing a `create` mutation for each.
//  Does NOT open the app — the interaction stays in Siri.
//

import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct AddShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Shopping List"
    static var description = IntentDescription("Add one or more items to your shared shopping list.")

    /// Stays in Siri — no app launch required.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", requestValueDialog: "What do you need?")
    var itemName: String

    init() {}

    init(itemName: String) {
        self.itemName = itemName
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let homeID = AppGroup.Context.currentHomeID else {
            return .result(dialog: "Sign in to Roost first to use this shortcut.")
        }

        let names = Self.splitItemNames(itemName)
        guard !names.isEmpty else {
            return .result(dialog: "I didn't catch that — what would you like to add?")
        }

        var addedCount = 0
        do {
            let container = try SharedShoppingReader.sharedModelContainer()
            let context = ModelContext(container)

            for name in names {
                let newID = UUID()
                let now = Date()

                let cached = CachedShoppingItem(
                    id: newID,
                    homeID: homeID,
                    name: name,
                    quantity: nil,
                    category: nil,
                    checked: false,
                    createdAt: now
                )
                cached.isDirty = true
                cached.pendingOperation = "create"
                context.insert(cached)

                let insert = InsertShoppingItem(
                    id: newID,
                    homeID: homeID,
                    name: name,
                    quantity: nil,
                    category: nil,
                    checked: false
                )
                let payload = ShoppingCreatePayload(item: insert)
                let payloadData = (try? JSONEncoder.mutation.encode(payload)) ?? Data()

                let mutation = PendingMutation(
                    entityType: "shopping_item",
                    operation: "create",
                    targetID: newID,
                    homeID: homeID,
                    payloadData: payloadData,
                    clientTimestamp: now,
                    deviceID: DeviceIdentity.current
                )
                context.insert(mutation)
                addedCount += 1
            }
            try context.save()
        } catch {
            return .result(dialog: "Something went wrong adding that — please try again.")
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "ShoppingWidget")

        let dialog: IntentDialog
        if addedCount == 1 {
            dialog = IntentDialog("Added \(names[0]) to the list.")
        } else {
            dialog = IntentDialog("Added \(addedCount) items to the list.")
        }
        return .result(dialog: dialog)
    }

    /// Splits user input like "milk, eggs and bread" into ["milk", "eggs", "bread"].
    static func splitItemNames(_ raw: String) -> [String] {
        let lowered = " " + raw + " "
        // Normalise " and " to a comma separator, then split.
        let normalised = lowered.replacingOccurrences(of: " and ", with: ", ")
        return normalised
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

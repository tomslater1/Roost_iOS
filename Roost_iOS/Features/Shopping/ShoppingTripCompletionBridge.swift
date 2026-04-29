//
//  ShoppingTripCompletionBridge.swift
//  Roost
//
//  Bridges a Live-Activity completion tap (`roost://shopping-trip-completed`)
//  into the main app. Sets a published flag that the Shopping list view
//  observes and acts on by navigating to the Money tab / presenting an
//  expense sheet pre-filled with the trip's store and the current user.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ShoppingTripCompletionBridge {
    static let shared = ShoppingTripCompletionBridge()

    /// True when a Live Activity completion tap is waiting to be handled by
    /// a view. Consumers should flip it back to false after acting.
    var pendingCompletion: Bool = false

    /// Store name captured when the trip was started (if any) — used to
    /// pre-fill the expense description.
    var suggestedMerchant: String?

    /// The time the trip was started, handy for the expense date.
    var tripStartedAt: Date?

    private init() {}

    /// Call from `onOpenURL` when the URL matches
    /// `roost://shopping-trip-completed`.
    func handle(url: URL) -> Bool {
        guard url.scheme == "roost", url.host == "shopping-trip-completed" else {
            return false
        }

        suggestedMerchant = AppGroup.Context.activeTripStoreName
        tripStartedAt = AppGroup.Context.activeTripStartedAt
        pendingCompletion = true

        // End the activity if it's still running (the user explicitly
        // tapped "Done" / "Log receipt").
        ShoppingTripManager.shared.endTrip(reason: .manual)

        return true
    }

    /// Mark the prompt as handled — called after the expense sheet is
    /// presented or dismissed.
    func clear() {
        pendingCompletion = false
        suggestedMerchant = nil
        tripStartedAt = nil
    }
}

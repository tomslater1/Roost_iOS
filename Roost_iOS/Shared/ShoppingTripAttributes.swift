//
//  ShoppingTripAttributes.swift
//  Roost
//
//  ActivityKit attributes for the Shopping Trip Live Activity.
//  Shared between the main app (which starts/updates/ends the activity)
//  and the RoostWidgets extension (which renders it).
//
//  Target membership: BOTH `Roost_iOS` and `RoostWidgets`.
//

import ActivityKit
import Foundation

struct ShoppingTripAttributes: ActivityAttributes {
    typealias ContentState = TripState

    // Static, non-changing context about the trip.
    let homeID: UUID
    let startedAt: Date
    let startedByUserID: UUID
    let startedByDisplayName: String?
    /// Optional store name captured when the trip was started (e.g. "Tesco").
    let storeName: String?

    struct TripState: Codable, Hashable {
        /// Total unchecked + checked items included in this trip snapshot.
        var totalItems: Int
        var checkedCount: Int
        /// First N unchecked items (typically 3) rendered inside the activity.
        var previewItems: [ShoppingItemDisplay]
        /// Set to true briefly after the final item is checked off, to trigger
        /// the completion UI before the activity ends.
        var isCompleted: Bool

        var remaining: Int { max(0, totalItems - checkedCount) }
        var progress: Double {
            guard totalItems > 0 else { return 0 }
            return Double(checkedCount) / Double(totalItems)
        }
    }
}

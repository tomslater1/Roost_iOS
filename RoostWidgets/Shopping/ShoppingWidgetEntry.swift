//
//  ShoppingWidgetEntry.swift
//  RoostWidgets
//

import Foundation
import WidgetKit

struct ShoppingWidgetEntry: TimelineEntry {
    let date: Date
    /// All items for the current home, ordered by display priority.
    /// Views slice this for their size (2 for small, 6 for medium, 10 for large).
    let items: [ShoppingItemDisplay]
    /// Total unchecked count across the whole list (not limited to `items`).
    let totalUnchecked: Int
    /// Total items (unchecked + checked). Used to drive progress rings.
    let totalAll: Int
    let householdName: String?
    /// True if the user is signed in and has a home. If false, widgets
    /// render a "Sign in" placeholder instead of the list UI.
    let isAuthenticated: Bool

    static let placeholder = ShoppingWidgetEntry(
        date: .now,
        items: [
            ShoppingItemDisplay(id: UUID(), name: "Milk", quantity: "2 pints", category: "Dairy", addedAt: .now),
            ShoppingItemDisplay(id: UUID(), name: "Bread", quantity: nil, category: "Bakery", addedAt: .now),
            ShoppingItemDisplay(id: UUID(), name: "Eggs", quantity: "12", category: "Dairy", addedAt: .now),
            ShoppingItemDisplay(id: UUID(), name: "Tomatoes", quantity: "500g", category: "Produce", addedAt: .now),
        ],
        totalUnchecked: 4,
        totalAll: 4,
        householdName: "Home",
        isAuthenticated: true
    )

    static let signedOut = ShoppingWidgetEntry(
        date: .now,
        items: [],
        totalUnchecked: 0,
        totalAll: 0,
        householdName: nil,
        isAuthenticated: false
    )
}

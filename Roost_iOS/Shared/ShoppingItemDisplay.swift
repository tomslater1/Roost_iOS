//
//  ShoppingItemDisplay.swift
//  Roost
//
//  Lightweight, Sendable display model used by the RoostWidgets extension
//  and the Live Activity views. Intentionally decoupled from SwiftData so
//  widget views don't have to know about ModelContainer at render time.
//
//  Target membership: BOTH `Roost_iOS` and `RoostWidgets`.
//

import Foundation
import SwiftUI

/// A snapshot of a shopping item, safe to pass across process boundaries
/// (widget timeline entries, Live Activity `ContentState`).
struct ShoppingItemDisplay: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let quantity: String?
    let category: String?
    let checked: Bool
    let addedAt: Date
    /// Display name of the member who added this item, if known. Used for
    /// the small author-dot affordance in medium/large widgets.
    let addedByName: String?
    /// Short emoji or symbol (optional) — reserved for category/item tinting.
    let emoji: String?

    init(
        id: UUID,
        name: String,
        quantity: String? = nil,
        category: String? = nil,
        checked: Bool = false,
        addedAt: Date = .now,
        addedByName: String? = nil,
        emoji: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.category = category
        self.checked = checked
        self.addedAt = addedAt
        self.addedByName = addedByName
        self.emoji = emoji
    }
}

extension ShoppingItemDisplay {
    /// Was this item added by someone *other* than the current user within
    /// the last 24 hours? Used by the widget's "fresh from partner" glow.
    func isFreshFromPartner(currentUserName: String?) -> Bool {
        guard let addedByName, let currentUserName else { return false }
        guard addedByName != currentUserName else { return false }
        return Date().timeIntervalSince(addedAt) < 86_400
    }

    /// Priority score for sorting in widget rows. Higher = shown first.
    /// Fresh partner-added items bubble to the top; otherwise most recent.
    func priorityScore(currentUserName: String?) -> Double {
        var score = addedAt.timeIntervalSince1970
        if isFreshFromPartner(currentUserName: currentUserName) {
            score += 86_400 * 10 // push well above normal ordering
        }
        return score
    }
}

// MARK: - SwiftData bridge

// Live in the main target where CachedShoppingItem lives (also compiled into
// the widget target because the model file is shared-membership).
extension ShoppingItemDisplay {
    /// Build a display snapshot from a SwiftData `CachedShoppingItem`.
    /// `memberDisplayName` is resolved by the caller (e.g. via
    /// `CachedHomeMember` lookup) so this factory stays SwiftData-free.
    static func from(
        cached: CachedShoppingItem,
        addedByName: String? = nil
    ) -> ShoppingItemDisplay {
        ShoppingItemDisplay(
            id: cached.id,
            name: cached.name,
            quantity: cached.quantity,
            category: cached.category,
            checked: cached.checked,
            addedAt: cached.createdAt,
            addedByName: addedByName,
            emoji: nil
        )
    }
}

import Foundation

struct ShoppingItem: Codable, Identifiable, Hashable {
    let id: UUID
    var homeID: UUID
    var name: String
    var quantity: String?
    var category: String?
    var checked: Bool
    var addedBy: UUID?
    var checkedBy: UUID?
    var createdAt: Date
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case name
        case quantity
        case category
        case checked
        case addedBy = "added_by"
        case checkedBy = "checked_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CreateShoppingItem: Codable, Hashable {
    var homeID: UUID
    var name: String
    var quantity: String?
    var category: String?

    enum CodingKeys: String, CodingKey {
        case homeID = "home_id"
        case name
        case quantity
        case category
    }
}

/// Like `CreateShoppingItem` but carries a client-supplied UUID so offline
/// creates can be queued and later replayed against the server without the
/// server inventing a new ID (which would desync the optimistic cache row).
struct InsertShoppingItem: Codable, Hashable {
    var id: UUID
    var homeID: UUID
    var name: String
    var quantity: String?
    var category: String?
    var checked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case name
        case quantity
        case category
        case checked
    }
}

/// Payload wrapper for queued "create" shopping mutations. Lives here (not
/// in `ShoppingMutationHandler.swift`) so the RoostWidgets extension can
/// encode the same shape the main app's handler decodes.
struct ShoppingCreatePayload: Codable {
    var item: InsertShoppingItem
}

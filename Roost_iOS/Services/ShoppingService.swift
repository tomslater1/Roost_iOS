import Foundation
import Supabase

struct ShoppingService {
    func fetchItems(for homeID: UUID) async throws -> [ShoppingItem] {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("shopping_items")
            .select()
            .eq("home_id", value: homeID)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createItem(_ item: CreateShoppingItem) async throws -> ShoppingItem {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("shopping_items")
            .insert(item)
            .select()
            .single()
            .execute()
            .value
    }

    /// Like `createItem`, but accepts a client-supplied UUID so offline
    /// writes can be queued and replayed without desyncing the optimistic
    /// cache row.
    func insertItem(_ item: InsertShoppingItem) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        try await client
            .from("shopping_items")
            .insert(item)
            .execute()
    }

    func updateItem(_ item: ShoppingItem) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        try await client
            .from("shopping_items")
            .update(item)
            .eq("id", value: item.id)
            .execute()
    }

    func deleteItem(id: UUID) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        try await client
            .from("shopping_items")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

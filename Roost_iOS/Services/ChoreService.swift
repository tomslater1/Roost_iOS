import Foundation
import Supabase

struct ChoreService {
    func fetchChores(for homeID: UUID) async throws -> [Chore] {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("chores")
            .select()
            .eq("home_id", value: homeID)
            .order("due_date")
            .execute()
            .value
    }

    func createChore(_ chore: CreateChore) async throws -> Chore {
        let client = try SupabaseClientProvider.shared.requireClient()
        return try await client
            .from("chores")
            .insert(chore)
            .select()
            .single()
            .execute()
            .value
    }

    /// Like `createChore`, but accepts a client-supplied UUID so offline
    /// writes can be queued and replayed without desyncing the optimistic
    /// cache row.
    func insertChore(_ chore: InsertChore) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        try await client
            .from("chores")
            .insert(chore)
            .execute()
    }

    func updateChore(_ chore: Chore) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        var payload: [String: AnyJSON] = [
            "home_id": .string(chore.homeID.uuidString),
            "title": .string(chore.title),
            "frequency": chore.frequency.map(AnyJSON.string) ?? .null
        ]

        payload["description"] = chore.description.map(AnyJSON.string) ?? .null
        payload["room"] = chore.room.map(AnyJSON.string) ?? .null
        payload["assigned_to"] = chore.assignedTo.map { .string($0.uuidString) } ?? .null
        payload["due_date"] = chore.dueDate.map { .string(Self.dateOnlyFormatter.string(from: $0)) } ?? .null
        payload["completed_by"] = chore.completedBy.map { .string($0.uuidString) } ?? .null
        payload["last_completed_at"] = chore.lastCompletedAt.map { .string(Self.timestampFormatter.string(from: $0)) } ?? .null

        try await client
            .from("chores")
            .update(payload)
            .eq("id", value: chore.id)
            .execute()
    }

    func deleteChore(id: UUID) async throws {
        let client = try SupabaseClientProvider.shared.requireClient()
        try await client
            .from("chores")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    private static let dateOnlyFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

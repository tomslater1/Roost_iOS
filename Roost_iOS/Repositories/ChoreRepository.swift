import Foundation
import SwiftData

// MARK: - ChoreRepository
//
// Cache-first reads for the chores list. Writes go through
// `OfflineAwareWrite.enqueue` — see `ChoreMutationHandler` for the
// replay side.
//
// Dirty-row policy matches `ExpenseRepository` / `ShoppingRepository`:
// a `CachedChore` whose `isDirty == true` is never overwritten by a
// server refresh until its pending mutation has drained. Server-side
// deletes are ignored on dirty local rows (a common race: "I completed
// this offline, my partner also deleted it" → the completion is preserved
// locally until drain, then reconciled normally on the next refresh).

@MainActor
struct ChoreRepository: Repository {
    typealias Model = Chore

    private let container: ModelContainer
    private let service: ChoreService

    init(container: ModelContainer? = nil, service: ChoreService = ChoreService()) {
        self.container = container ?? LocalDataManager.shared.container
        self.service = service
    }

    // MARK: Cache reads

    func loadCached(homeID: UUID) throws -> [Chore] {
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedChore>(
            predicate: #Predicate { $0.homeID == homeID },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        return try context.fetch(descriptor).map { row in
            Chore(
                id: row.id,
                homeID: row.homeID,
                title: row.title,
                description: row.choreDescription,
                room: row.room,
                assignedTo: row.assignedTo,
                dueDate: row.dueDate,
                completedBy: row.completedBy,
                frequency: row.frequency,
                lastCompletedAt: row.lastCompletedAt,
                createdAt: row.createdAt
            )
        }
    }

    // MARK: Refresh

    func refresh(homeID: UUID) async throws {
        let fresh = try await service.fetchChores(for: homeID)
        try upsertLocal(fresh, homeID: homeID)
    }

    // MARK: Cache merge (server → cache, dirty-preserving)

    func upsertLocal(_ chores: [Chore], homeID: UUID) throws {
        let context = container.mainContext
        let existing = try context.fetch(
            FetchDescriptor<CachedChore>(predicate: #Predicate { $0.homeID == homeID })
        )
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(chores.map(\.id))
        let now = Date()

        for cached in existing where !incomingIDs.contains(cached.id) && !cached.isDirty {
            context.delete(cached)
        }

        for chore in chores {
            if let row = existingByID[chore.id] {
                if row.isDirty { continue } // local write wins until drain
                row.homeID = chore.homeID
                row.title = chore.title
                row.choreDescription = chore.description
                row.room = chore.room
                row.completedBy = chore.completedBy
                row.assignedTo = chore.assignedTo
                row.dueDate = chore.dueDate
                row.frequency = chore.frequency
                row.lastCompletedAt = chore.lastCompletedAt
                row.createdAt = chore.createdAt
                row.lastSyncedAt = now
                row.pendingOperation = nil
            } else {
                let fresh = CachedChore(from: chore)
                fresh.lastSyncedAt = now
                context.insert(fresh)
            }
        }

        try context.save()
    }

    // MARK: Optimistic cache writes

    func applyOptimisticUpsert(_ chore: Chore, pendingOperation: String) throws {
        let context = container.mainContext
        let choreID = chore.id
        let existing = try context.fetch(
            FetchDescriptor<CachedChore>(predicate: #Predicate { $0.id == choreID })
        ).first

        if let row = existing {
            row.homeID = chore.homeID
            row.title = chore.title
            row.choreDescription = chore.description
            row.room = chore.room
            row.completedBy = chore.completedBy
            row.assignedTo = chore.assignedTo
            row.dueDate = chore.dueDate
            row.frequency = chore.frequency
            row.lastCompletedAt = chore.lastCompletedAt
            row.isDirty = true
            row.pendingOperation = pendingOperation
        } else {
            let fresh = CachedChore(from: chore)
            fresh.isDirty = true
            fresh.pendingOperation = pendingOperation
            context.insert(fresh)
        }
        try context.save()
    }

    func applyOptimisticDelete(choreID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedChore>(predicate: #Predicate { $0.id == choreID })
        ).first {
            context.delete(row)
        }
        try context.save()
    }

    // MARK: Drain hooks

    func clearDirty(choreID: UUID) throws {
        let context = container.mainContext
        if let row = try context.fetch(
            FetchDescriptor<CachedChore>(predicate: #Predicate { $0.id == choreID })
        ).first {
            row.isDirty = false
            row.pendingOperation = nil
        }
        try context.save()
    }

    // MARK: Repository conformance fallback

    func upsertLocal(_ chores: [Chore]) throws {
        guard let homeID = chores.first?.homeID else { return }
        try upsertLocal(chores, homeID: homeID)
    }
}

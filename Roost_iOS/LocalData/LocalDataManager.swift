import Foundation
import SwiftData

@MainActor
final class LocalDataManager {
    static let shared = LocalDataManager()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            // Pre-offline models (Phase 0 — extended in-place with offline metadata).
            CachedShoppingItem.self,
            CachedExpense.self,
            CachedChore.self,
            CachedActivityFeedItem.self,
            // Phase 1 offline foundation — additional domain caches.
            CachedExpenseSplit.self,
            CachedBudget.self,
            CachedCustomCategory.self,
            CachedSavingsGoal.self,
            CachedCalendarEvent.self,
            CachedPinboardNote.self,
            CachedRoom.self,
            CachedHome.self,
            CachedHomeMember.self,
            CachedHouseholdIncome.self,
            // Phase 1 offline foundation — mutation outbox.
            PendingMutation.self,
        ])

        // Prefer the App Group container so the RoostWidgets extension can
        // read/write the same SwiftData store. Fall back to the default
        // location if the App Group isn't available (e.g. unit tests).
        let configuration: ModelConfiguration
        if let sharedStoreURL = AppGroup.swiftDataStoreURL {
            Self.migrateLegacyStoreIfNeeded(to: sharedStoreURL, schema: schema)
            configuration = ModelConfiguration(schema: schema, url: sharedStoreURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Schema migration failure — wipe the store and start fresh rather than crashing.
            try? FileManager.default.removeItem(at: configuration.url)
            do {
                container = try ModelContainer(for: schema, configurations: configuration)
            } catch {
                // Fall back to in-memory store so the app remains usable.
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try! ModelContainer(for: schema, configurations: memoryConfig)
            }
        }
    }

    /// On first launch after the App Group migration, copy the user's existing
    /// SwiftData store from the default location into the App Group container.
    /// Idempotent: does nothing if the App Group store already exists or if
    /// there's no legacy store to migrate.
    private static func migrateLegacyStoreIfNeeded(to newURL: URL, schema: Schema) {
        let fm = FileManager.default

        // If the shared store already exists, migration has already happened.
        if fm.fileExists(atPath: newURL.path) { return }

        // Determine the legacy (default) location SwiftData would have used.
        let legacyConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let legacyURL = legacyConfig.url
        guard fm.fileExists(atPath: legacyURL.path) else { return }

        // Copy the main store plus SQLite sidecar files (-wal and -shm).
        let suffixes = ["", "-wal", "-shm"]
        do {
            for suffix in suffixes {
                let src = URL(fileURLWithPath: legacyURL.path + suffix)
                let dst = URL(fileURLWithPath: newURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.copyItem(at: src, to: dst)
            }
        } catch {
            // If anything goes wrong, leave the App Group store empty and
            // let the app rebuild from Supabase. Better than blocking launch.
            try? fm.removeItem(at: newURL)
        }
    }
}

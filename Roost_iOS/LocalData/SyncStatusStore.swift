import Foundation
import Observation

/// Single source of truth for offline-sync UI state.
///
/// Driven by `SyncCoordinator` and `NetworkMonitor`; consumed by the
/// `OfflineBanner` at the app root, the per-item `PendingChangeBadge`, and
/// the Settings → Pending Changes review screen.
@MainActor
@Observable
final class SyncStatusStore {
    static let shared = SyncStatusStore()

    /// Coarse-grained state for the offline banner.
    enum State: Equatable {
        /// Everything is synced, nothing in the queue.
        case idle
        /// Online and currently replaying queued mutations.
        case syncing(pending: Int)
        /// No network; the user is in full offline mode.
        case offline
        /// One or more mutations have failed permanently and need user action.
        case error(failed: Int)
    }

    var state: State = .idle

    /// Number of mutations currently in the queue (pending + inFlight).
    /// Surfaced in per-item badges and the "Syncing N…" banner.
    var pendingCount: Int = 0

    /// Number of mutations in the `failed` status — shown as a red dot in
    /// Settings until the user retries or discards them.
    var failedCount: Int = 0

    /// Incremented once per drain that encounters a server-side conflict
    /// (LWW — server wins). The UI surfaces a one-shot toast when this
    /// changes, then resets `lastAcknowledgedReconciliation` to match.
    var reconciliationCount: Int = 0
    var lastAcknowledgedReconciliation: Int = 0

    /// Incremented once per drain cycle that successfully replayed at least
    /// one mutation. Observers hook post-drain work (e.g. Hazel deferred
    /// categorisation of expenses that were created offline without a
    /// category) by watching this counter.
    var drainCompletedCount: Int = 0

    var hasUnacknowledgedReconciliation: Bool {
        reconciliationCount > lastAcknowledgedReconciliation
    }

    func acknowledgeReconciliation() {
        lastAcknowledgedReconciliation = reconciliationCount
    }

    /// Internal init for test injection. Production code should always go
    /// through `SyncStatusStore.shared`.
    init() {}
}

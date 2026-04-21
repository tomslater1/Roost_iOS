import Foundation
import Observation

// MARK: - MutationHandler

/// A per-domain replay handler. Each domain (expenses, budgets, shopping, …)
/// registers one handler at app boot. The coordinator looks up the handler by
/// `entityType` when draining the queue.
///
/// Handlers are expected to:
///   - Decode `mutation.payloadData` into the domain's request shape.
///   - Call the relevant service method.
///   - Upsert the server's authoritative response into the SwiftData cache
///     and clear the row's `isDirty`/`pendingOperation` flags.
///
/// Handlers throw one of the outcomes in `MutationHandlerError` so the
/// coordinator knows how to classify the failure.
@MainActor
protocol MutationHandler {
    /// The logical entity type this handler is responsible for, e.g. "expense".
    var entityType: String { get }

    /// Replays a single mutation against the server.
    /// Throws `MutationHandlerError` to signal the outcome.
    func replay(_ mutation: PendingMutation) async throws
}

/// Errors a `MutationHandler` can throw to influence the coordinator's
/// retry/backoff behaviour.
enum MutationHandlerError: Error {
    /// Transient failure (network, timeout, 5xx). Retry with backoff.
    case transient(String)
    /// Permanent failure (4xx, validation, permission). Move to `.failed`
    /// for user review; do not auto-retry.
    case permanent(String)
    /// Server rejected the mutation because the underlying row was modified
    /// concurrently (409, constraint violation). Under LWW, the server wins —
    /// the coordinator treats this as a successful reconcile and bumps the
    /// reconciliationCount for the UI toast.
    case reconciledByServer(String)
    /// Auth token expired or invalid. Pause drain; try again after next
    /// successful token refresh.
    case authExpired
}

// MARK: - SyncCoordinator

/// Singleton that drains the offline `MutationQueue` when it's safe to do so
/// (online + authenticated + foreground).
///
/// Trigger points:
///   - App becomes active (scenePhase == .active).
///   - NetworkMonitor transitions to `isConnected == true`.
///   - Auth becomes authenticated after being unauthenticated.
///   - Any ViewModel call to `OfflineAwareWrite.enqueue(_:)` attempts an
///     immediate drain for responsiveness.
///
/// Drain loop:
///   1. Pulls a batch via `MutationQueue.nextBatch(limit:)`.
///   2. For each mutation, looks up the registered `MutationHandler` by
///      `entityType` and awaits its `replay`.
///   3. Classifies the result and updates the queue accordingly.
///   4. Keeps draining until the batch is empty or the network drops.
@MainActor
@Observable
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    // MARK: Dependencies (injected at app launch)

    @ObservationIgnored
    private weak var networkMonitor: NetworkMonitor?

    @ObservationIgnored
    private weak var authManager: AuthManager?

    // MARK: Handler registry

    @ObservationIgnored
    private var handlers: [String: any MutationHandler] = [:]

    /// Registers a per-domain handler. Call from app init or from each
    /// ViewModel's startup in Phase 2+.
    func register(_ handler: any MutationHandler) {
        handlers[handler.entityType] = handler
    }

    // MARK: State

    /// True while a drain is actively running — prevents re-entrancy.
    @ObservationIgnored
    private var isDraining = false

    // MARK: Wiring

    func configure(networkMonitor: NetworkMonitor, authManager: AuthManager) {
        self.networkMonitor = networkMonitor
        self.authManager = authManager
        refreshStatusCounts()
    }

    // MARK: Public drain triggers

    /// Called on "something might have changed" events (network reconnect,
    /// app foreground, fresh enqueue). Safe to call often — it's idempotent.
    func drainIfOnline() async {
        guard canDrain() else {
            updateBannerState()
            return
        }
        await drain()
    }

    /// Forces a drain attempt ignoring online-state gating — used by tests
    /// and by the "Retry" action in the Pending Changes UI.
    func drain() async {
        guard !isDraining else { return }
        isDraining = true
        var anySucceeded = false
        defer {
            isDraining = false
            refreshStatusCounts()
            if anySucceeded {
                // Post-drain hook for consumers (e.g. Hazel bulk categorisation
                // of offline-created expenses that landed without a category).
                SyncStatusStore.shared.drainCompletedCount += 1
            }
        }

        let queue = MutationQueue()
        do {
            var batch = try queue.nextBatch(limit: 25)
            while !batch.isEmpty {
                for mutation in batch {
                    // Re-check connectivity between rows — network may have
                    // dropped mid-drain and subsequent rows should stop.
                    guard canDrain() else { return }
                    let succeeded = await replay(mutation, via: queue)
                    if succeeded { anySucceeded = true }
                }
                batch = try queue.nextBatch(limit: 25)
            }
        } catch {
            // Unable to read the queue. Surface via banner but don't crash.
            SyncStatusStore.shared.state = .error(failed: (try? queue.failedCount()) ?? 0)
        }
    }

    /// Refreshes pending/failed counts and updates the banner state.
    /// Safe to call after any queue mutation.
    func refreshStatusCounts() {
        let queue = MutationQueue()
        let pending = (try? queue.pendingCount()) ?? 0
        let failed = (try? queue.failedCount()) ?? 0
        SyncStatusStore.shared.pendingCount = pending
        SyncStatusStore.shared.failedCount = failed
        updateBannerState(pending: pending, failed: failed)
    }

    // MARK: Private replay

    /// Returns true if the mutation was replayed successfully (including the
    /// LWW "reconciled by server" outcome, which is treated as success at the
    /// queue level). Used by `drain()` to decide whether to bump the
    /// post-drain hook counter.
    @discardableResult
    private func replay(_ mutation: PendingMutation, via queue: MutationQueue) async -> Bool {
        guard let handler = handlers[mutation.entityType] else {
            // No handler registered — this is a permanent failure from the
            // coordinator's perspective. Surface for user review.
            try? queue.markFailed(
                mutation.id,
                error: "No handler registered for \(mutation.entityType).",
                terminal: true
            )
            return false
        }

        try? queue.markInFlight(mutation.id)

        do {
            try await handler.replay(mutation)
            try? queue.markSucceeded(mutation.id)
            return true
        } catch let error as MutationHandlerError {
            switch error {
            case .transient(let msg):
                try? queue.markFailed(mutation.id, error: msg, terminal: false)
                return false
            case .permanent(let msg):
                try? queue.markFailed(mutation.id, error: msg, terminal: true)
                return false
            case .reconciledByServer(let msg):
                // LWW — server wins. We count this as "success" for the queue
                // but bump the reconciliation counter so the UI can show a
                // one-shot toast.
                try? queue.markSucceeded(mutation.id)
                SyncStatusStore.shared.reconciliationCount += 1
                _ = msg
                return true
            case .authExpired:
                // Stop the drain for this cycle; the auth layer will retry
                // when a fresh token is available.
                try? queue.markFailed(mutation.id, error: "Session expired.", terminal: false)
                return false
            }
        } catch {
            // Unknown / non-classified error — treat as transient.
            try? queue.markFailed(mutation.id, error: error.localizedDescription, terminal: false)
            return false
        }
    }

    // MARK: Gating

    private func canDrain() -> Bool {
        guard let networkMonitor, networkMonitor.isConnected else { return false }
        guard let authManager, authManager.isAuthenticated else { return false }
        return true
    }

    private func updateBannerState(pending: Int? = nil, failed: Int? = nil) {
        let store = SyncStatusStore.shared
        let p = pending ?? store.pendingCount
        let f = failed ?? store.failedCount

        let online = networkMonitor?.isConnected ?? true
        if !online {
            store.state = .offline
            return
        }
        if f > 0 {
            store.state = .error(failed: f)
            return
        }
        if p > 0 {
            store.state = .syncing(pending: p)
            return
        }
        store.state = .idle
    }

    private init() {}
}

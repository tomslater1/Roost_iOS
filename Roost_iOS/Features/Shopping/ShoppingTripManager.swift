//
//  ShoppingTripManager.swift
//  Roost
//
//  Owns the lifecycle of a Shopping Trip Live Activity.
//  Responsibilities:
//    • Starting a trip (Activity.request)
//    • Pushing ContentState updates when items change
//    • Ending a trip (manual or auto on completion)
//    • Rebinding to an existing Activity when the app relaunches mid-trip
//
//  Lives in the main app target only (ActivityKit lifecycle APIs can't
//  be driven from the widget extension). Tap interactions inside the
//  Activity go through App Intents in the widget extension instead.
//

import ActivityKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ShoppingTripManager {
    static let shared = ShoppingTripManager()

    /// Currently-running activity, if any.
    @ObservationIgnored
    private var activity: Activity<ShoppingTripAttributes>?

    /// Auto-end timer for the "all items checked" grace period.
    @ObservationIgnored
    private var completionTimer: Task<Void, Never>?

    var isActive: Bool { activity != nil }

    private init() {}

    // MARK: - Start / End

    /// Starts a new Shopping Trip Live Activity for the given home/user.
    /// No-op if a trip is already running.
    func startTrip(homeID: UUID, userID: UUID, userDisplayName: String?, storeName: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // User has Live Activities disabled in Settings. Silently skip.
            return
        }
        if activity != nil { return }

        let attributes = ShoppingTripAttributes(
            homeID: homeID,
            startedAt: Date(),
            startedByUserID: userID,
            startedByDisplayName: userDisplayName,
            storeName: storeName
        )
        let state = SharedShoppingReader.currentTripState()

        do {
            let newActivity: Activity<ShoppingTripAttributes>
            if #available(iOS 16.2, *) {
                newActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } else {
                newActivity = try Activity.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil
                )
            }
            self.activity = newActivity

            // Persist context so the widget extension can find it.
            AppGroup.Context.activeTripActivityID = newActivity.id
            AppGroup.Context.activeTripStartedAt = attributes.startedAt
            AppGroup.Context.activeTripStoreName = storeName
        } catch {
            // If the request fails, leave the app state as if no trip started.
        }
    }

    /// Ends the current activity (if any) and clears shared state.
    func endTrip(reason: EndReason = .manual) {
        completionTimer?.cancel()
        completionTimer = nil

        guard let activity else {
            AppGroup.Context.activeTripActivityID = nil
            AppGroup.Context.activeTripStartedAt = nil
            AppGroup.Context.activeTripStoreName = nil
            return
        }

        let finalState = SharedShoppingReader.currentTripState()

        Task {
            if #available(iOS 16.2, *) {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: reason == .timedOut ? .immediate : .default
                )
            } else {
                await activity.end(using: finalState, dismissalPolicy: .default)
            }
        }

        self.activity = nil
        AppGroup.Context.activeTripActivityID = nil
        AppGroup.Context.activeTripStartedAt = nil
        AppGroup.Context.activeTripStoreName = nil
    }

    enum EndReason {
        case manual
        case autoCompleted
        case timedOut
    }

    // MARK: - Updates

    /// Rebuild the ContentState from current SwiftData and push to the activity.
    /// Called whenever an item is added / checked / removed.
    func refreshActiveActivity() {
        guard let activity else { return }
        let state = SharedShoppingReader.currentTripState()

        Task {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            } else {
                await activity.update(using: state)
            }
        }

        // If the trip just completed, schedule an auto-end.
        if state.isCompleted {
            scheduleAutoEndIfNeeded()
        } else {
            completionTimer?.cancel()
            completionTimer = nil
        }
    }

    private func scheduleAutoEndIfNeeded() {
        completionTimer?.cancel()
        completionTimer = Task { [weak self] in
            // 60-second grace period so the user can tap "Log receipt" before
            // the activity disappears. If they don't, we end gracefully.
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.endTrip(reason: .autoCompleted)
        }
    }

    // MARK: - Restore

    /// Call on app launch. If an activity is still running from a previous
    /// session, bind to it so updates/ends continue to work.
    func restoreActiveActivityIfAny() {
        if #available(iOS 16.1, *) {
            if let existing = Activity<ShoppingTripAttributes>.activities.first {
                self.activity = existing
                AppGroup.Context.activeTripActivityID = existing.id
                AppGroup.Context.activeTripStartedAt = existing.attributes.startedAt
                AppGroup.Context.activeTripStoreName = existing.attributes.storeName
            } else {
                // No activity is running — clear any stale context.
                AppGroup.Context.activeTripActivityID = nil
                AppGroup.Context.activeTripStartedAt = nil
                AppGroup.Context.activeTripStoreName = nil
            }
        }
    }
}

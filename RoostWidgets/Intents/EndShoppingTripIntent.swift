//
//  EndShoppingTripIntent.swift
//  RoostWidgets
//
//  Tapped from the Live Activity "Done" affordance. Opens the main app
//  with a `roost://shopping-trip-completed` deep link so the app can
//  show the receipt-logging bridge and end the Activity in-process.
//

import ActivityKit
import AppIntents
import Foundation

struct EndShoppingTripIntent: AppIntent {
    static var title: LocalizedStringResource = "End Shopping Trip"
    static var description = IntentDescription("Finish the current shopping trip and optionally log the receipt.")

    /// Opens the app so the main process can end the ActivityKit activity
    /// and present the "Log as expense?" bridge.
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // `openAppWhenRun = true` brings the app forward. The app inspects
        // this timestamp on foregrounding and presents the completion bridge.
        // Avoids iOS 18's `OpenURLIntent` so we can stay on iOS 17.
        AppGroup.defaults.set(Date().timeIntervalSince1970,
                              forKey: "roost.pendingTripCompletionAt")
        return .result()
    }
}

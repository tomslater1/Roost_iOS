//
//  StartShoppingTripIntent.swift
//  RoostWidgets
//
//  "Hey Siri, start shopping" — opens Roost so ActivityKit can request a
//  new Live Activity in the main app's process (widget extensions can't
//  start activities themselves).
//

import AppIntents
import Foundation

struct StartShoppingTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Shopping Trip"
    static var description = IntentDescription("Open Roost to start a shopping trip Live Activity.")

    /// `openAppWhenRun` brings the app to the foreground; the app reads the
    /// `pendingTripStart` flag below on launch and auto-presents the start
    /// prompt. Using this flag avoids needing iOS 18's `OpenURLIntent`.
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // Flag in shared UD so the app knows to auto-present the start prompt.
        AppGroup.defaults.set(true, forKey: "roost.pendingTripStart")
        return .result()
    }
}

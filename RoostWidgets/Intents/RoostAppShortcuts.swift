//
//  RoostAppShortcuts.swift
//  RoostWidgets
//
//  Exposes Roost's App Intents to Siri and the Shortcuts app as
//  "App Shortcuts" — these show up automatically in Siri suggestions,
//  Spotlight, and the Shortcuts gallery without the user having to
//  configure anything.
//

import AppIntents

struct RoostAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // `itemName` is a plain String, so AppShortcut phrases can't embed it
        // directly (App Shortcuts only support AppEntity/AppEnum parameters).
        // Siri still prompts for the item name via `requestValueDialog` once
        // the shortcut is invoked.
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add to my \(.applicationName) shopping list",
                "Add something to the \(.applicationName) shopping list"
            ],
            shortTitle: "Add to Shopping List",
            systemImageName: "cart.badge.plus"
        )

        AppShortcut(
            intent: StartShoppingTripIntent(),
            phrases: [
                "Start a \(.applicationName) shopping trip",
                "Begin shopping in \(.applicationName)"
            ],
            shortTitle: "Start Shopping Trip",
            systemImageName: "cart.fill"
        )
    }
}

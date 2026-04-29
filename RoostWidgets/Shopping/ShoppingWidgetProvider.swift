//
//  ShoppingWidgetProvider.swift
//  RoostWidgets
//
//  TimelineProvider that pulls from the shared SwiftData store.
//  Widget refresh is driven by three things:
//    1. `WidgetCenter.reloadTimelines` calls from the main app on writes.
//    2. Our own `reloadTimelines` calls inside App Intents after a tap.
//    3. A polite 30-minute fallback timeline policy for idle refresh.
//

import Foundation
import WidgetKit

struct ShoppingWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShoppingWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ShoppingWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShoppingWidgetEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh at least every 30 minutes even if nobody touches the app.
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    // MARK: - Data

    private func currentEntry() -> ShoppingWidgetEntry {
        guard AppGroup.Context.currentHomeID != nil else {
            return .signedOut
        }

        let all = SharedShoppingReader.fetchItems(limit: 40)
        let unchecked = all.filter { !$0.checked }

        return ShoppingWidgetEntry(
            date: .now,
            items: unchecked,
            totalUnchecked: unchecked.count,
            totalAll: all.count,
            householdName: nil, // Reserved for future: pull CachedHome.name
            isAuthenticated: true
        )
    }
}

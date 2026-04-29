//
//  ShoppingWidgetLockScreenViews.swift
//  RoostWidgets
//
//  Lock Screen accessory widget views. Lock screen widgets can't use
//  interactive buttons (taps always open the app), so these are read-only
//  summaries that deep link into `roost://shopping`.
//

import SwiftUI
import WidgetKit

/// Circular: progress ring + remaining count at the centre.
struct ShoppingWidgetAccessoryCircularView: View {
    let entry: ShoppingWidgetEntry

    var body: some View {
        if entry.totalAll == 0 {
            Image(systemName: "cart")
                .widgetAccentable()
        } else {
            let checked = entry.totalAll - entry.totalUnchecked
            let progress = entry.totalAll > 0 ? Double(checked) / Double(entry.totalAll) : 0
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: progress) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 10, weight: .semibold))
                } currentValueLabel: {
                    Text("\(entry.totalUnchecked)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            }
            .widgetURL(URL(string: "roost://shopping"))
        }
    }
}

/// Rectangular: cart icon + count line + top 2 items.
struct ShoppingWidgetAccessoryRectangularView: View {
    let entry: ShoppingWidgetEntry

    var body: some View {
        if entry.totalAll == 0 {
            HStack(spacing: 4) {
                Image(systemName: "cart")
                Text("No items")
            }
            .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("^[\(entry.totalUnchecked) item](inflect: true) to buy")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .widgetAccentable()

                ForEach(entry.items.prefix(2)) { item in
                    Text("• \(item.name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "roost://shopping"))
        }
    }
}

/// Inline: single line, rendered by the system as a status string.
struct ShoppingWidgetAccessoryInlineView: View {
    let entry: ShoppingWidgetEntry

    var body: some View {
        if entry.totalAll == 0 {
            Label("No shopping", systemImage: "cart")
        } else {
            Label("\(entry.totalUnchecked) to buy", systemImage: "cart")
        }
    }
}

//
//  ShoppingWidget.swift
//  RoostWidgets
//
//  Top-level widget declaration. Registers supported families and the entry
//  view switcher that picks the right layout per size.
//

import SwiftUI
import WidgetKit

struct ShoppingWidget: Widget {
    static let kind = "ShoppingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ShoppingWidgetProvider()) { entry in
            ShoppingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Shopping List")
        .description("See what's on the list — and tick items off from your home screen.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}

/// Picks the correct size-specific view based on `WidgetFamily`.
struct ShoppingWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShoppingWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                ShoppingWidgetSmallView(entry: entry)
            case .systemMedium:
                ShoppingWidgetMediumView(entry: entry)
            case .systemLarge:
                ShoppingWidgetLargeView(entry: entry)
            case .accessoryCircular:
                ShoppingWidgetAccessoryCircularView(entry: entry)
            case .accessoryRectangular:
                ShoppingWidgetAccessoryRectangularView(entry: entry)
            case .accessoryInline:
                ShoppingWidgetAccessoryInlineView(entry: entry)
            default:
                ShoppingWidgetMediumView(entry: entry)
            }
        }
    }
}

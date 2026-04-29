//
//  ShoppingLiveActivity.swift
//  RoostWidgets
//
//  ActivityKit Live Activity for an in-progress shopping trip.
//  Renders on the lock screen + in Dynamic Island while the user is
//  shopping. The activity's ContentState is kept fresh by the main app
//  (see ShoppingTripManager) and by tap-triggered intents running in
//  this extension (ToggleShoppingItemIntent).
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingTripAttributes.self) { context in
            // Lock screen / banner UI.
            ShoppingTripLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.95))
            .activitySystemActionForegroundColor(.orange)

        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED — the "tall" layout when user long-presses the pill.
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "cart.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text("\(context.state.checkedCount)/\(context.state.totalItems)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        if let store = context.attributes.storeName {
                            Text(store)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .relative)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        // Next couple of unchecked items with tap-to-check.
                        ForEach(context.state.previewItems.prefix(2)) { item in
                            ShoppingLiveActivityRow(item: item, tint: .orange)
                        }

                        HStack {
                            Link(destination: URL(string: "roost://shopping")!) {
                                Label("Open", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Spacer()
                            Button(intent: EndShoppingTripIntent()) {
                                Label("Done", systemImage: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .tint(.orange)
                        }
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(context.state.checkedCount)/\(context.state.totalItems)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "roost://shopping"))
            .keylineTint(.orange)
        }
    }
}

/// Compact row used inside the Live Activity (both lock screen and DI).
struct ShoppingLiveActivityRow: View {
    let item: ShoppingItemDisplay
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleShoppingItemIntent(itemID: item.id.uuidString)) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.3)
                        .frame(width: 18, height: 18)
                    if item.checked {
                        Circle().fill(tint).frame(width: 12, height: 12)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(item.checked ? .secondary : .primary)
                .strikethrough(item.checked, color: .secondary)
                .lineLimit(1)

            if let quantity = item.quantity, !quantity.isEmpty {
                Text(quantity)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

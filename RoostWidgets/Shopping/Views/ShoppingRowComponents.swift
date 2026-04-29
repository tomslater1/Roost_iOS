//
//  ShoppingRowComponents.swift
//  RoostWidgets
//
//  Shared row + chrome pieces for the Shopping widget sizes.
//  All views here are stateless; tap handling lives in the intent buttons.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Compact row used inside the Medium and Large widgets.
/// The check circle is a `Button(intent:)` so tapping it toggles the item
/// via `ToggleShoppingItemIntent` without opening the app.
struct ShoppingWidgetRow: View {
    let item: ShoppingItemDisplay
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            // Category stripe — left accent bar.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(categoryColor.opacity(0.85))
                .frame(width: 3, height: 22)

            // Tap target: the check circle runs ToggleShoppingItemIntent.
            Button(intent: ToggleShoppingItemIntent(itemID: item.id.uuidString)) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            item.checked ? tint : Color.primary.opacity(0.35),
                            lineWidth: 1.5
                        )
                        .frame(width: 20, height: 20)
                    if item.checked {
                        Circle().fill(tint).frame(width: 14, height: 14)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.checked ? "Uncheck \(item.name)" : "Check \(item.name)")

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.checked ? .secondary : .primary)
                    .strikethrough(item.checked, color: .secondary)
                    .lineLimit(1)
                if let quantity = item.quantity, !quantity.isEmpty {
                    Text(quantity)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryColor: Color {
        ShoppingWidgetRow.color(forCategory: item.category)
    }

    static func color(forCategory category: String?) -> Color {
        guard let c = category?.lowercased() else { return .secondary.opacity(0.4) }
        switch c {
        case "produce", "fruit", "vegetables": return .green
        case "dairy": return .blue
        case "bakery", "bread": return .brown
        case "meat", "fish", "protein": return .red
        case "frozen": return .cyan
        case "pantry", "dry goods": return .orange
        case "household", "cleaning": return .purple
        case "personal", "health": return .pink
        default: return .secondary.opacity(0.6)
        }
    }
}

/// Header strip shown at the top of small/medium/large widgets.
struct ShoppingWidgetHeader: View {
    let totalUnchecked: Int
    let totalAll: Int
    let tint: Color
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cart.fill")
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(tint)
            Text("Shopping")
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if totalUnchecked > 0 {
                Text("\(totalUnchecked)")
                    .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tint))
            }
        }
    }
}

/// Empty state — shown when the list is 0 items.
struct ShoppingWidgetEmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "cart")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing to buy")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// All-checked state — every item in the list is ticked off.
struct ShoppingWidgetAllDoneState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.green)
            Text("All done!")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Signed-out state — deep-links into the app.
struct ShoppingWidgetSignedOutState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text("Sign in to Roost")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

//
//  ShoppingWidgetMediumView.swift
//  RoostWidgets
//

import SwiftUI
import WidgetKit

struct ShoppingWidgetMediumView: View {
    let entry: ShoppingWidgetEntry

    private let tint: Color = .orange  // Matches Color.roostShoppingTint semantics

    var body: some View {
        if !entry.isAuthenticated {
            ShoppingWidgetSignedOutState()
                .padding(12)
        } else if entry.totalAll == 0 {
            ShoppingWidgetEmptyState()
                .padding(12)
        } else if entry.totalUnchecked == 0 {
            ShoppingWidgetAllDoneState()
                .padding(12)
        } else {
            content
                .padding(12)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShoppingWidgetHeader(
                totalUnchecked: entry.totalUnchecked,
                totalAll: entry.totalAll,
                tint: tint,
                compact: false
            )

            // Up to 4 items visible in the medium size.
            VStack(spacing: 4) {
                ForEach(entry.items.prefix(4)) { item in
                    ShoppingWidgetRow(item: item, tint: tint)
                }
            }

            Spacer(minLength: 0)

            // "more to go" hint if we truncated the list.
            if entry.totalUnchecked > 4 {
                Text("+\(entry.totalUnchecked - 4) more")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Tapping the chrome (anywhere that isn't a check circle) opens the app.
        .widgetURL(URL(string: "roost://shopping"))
    }
}

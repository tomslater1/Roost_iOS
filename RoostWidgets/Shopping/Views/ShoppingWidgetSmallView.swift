//
//  ShoppingWidgetSmallView.swift
//  RoostWidgets
//

import SwiftUI
import WidgetKit

struct ShoppingWidgetSmallView: View {
    let entry: ShoppingWidgetEntry
    private let tint: Color = .orange

    var body: some View {
        if !entry.isAuthenticated {
            ShoppingWidgetSignedOutState().padding(10)
        } else if entry.totalAll == 0 {
            ShoppingWidgetEmptyState().padding(10)
        } else if entry.totalUnchecked == 0 {
            ShoppingWidgetAllDoneState().padding(10)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ShoppingWidgetHeader(
                    totalUnchecked: entry.totalUnchecked,
                    totalAll: entry.totalAll,
                    tint: tint,
                    compact: true
                )

                VStack(spacing: 3) {
                    ForEach(entry.items.prefix(2)) { item in
                        ShoppingWidgetRow(item: item, tint: tint)
                    }
                }

                Spacer(minLength: 0)

                if entry.totalUnchecked > 2 {
                    Text("+\(entry.totalUnchecked - 2) more")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "roost://shopping"))
        }
    }
}

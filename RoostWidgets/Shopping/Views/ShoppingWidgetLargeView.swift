//
//  ShoppingWidgetLargeView.swift
//  RoostWidgets
//

import SwiftUI
import WidgetKit

struct ShoppingWidgetLargeView: View {
    let entry: ShoppingWidgetEntry
    private let tint: Color = .orange

    var body: some View {
        if !entry.isAuthenticated {
            ShoppingWidgetSignedOutState().padding(14)
        } else if entry.totalAll == 0 {
            ShoppingWidgetEmptyState().padding(14)
        } else if entry.totalUnchecked == 0 {
            ShoppingWidgetAllDoneState().padding(14)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ShoppingWidgetHeader(
                    totalUnchecked: entry.totalUnchecked,
                    totalAll: entry.totalAll,
                    tint: tint,
                    compact: false
                )

                // Up to 10 items, grouped by category if there's more than one.
                let items = Array(entry.items.prefix(10))
                let groups = groupByCategory(items)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups, id: \.category) { group in
                        if groups.count > 1 {
                            Text(group.category.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }
                        VStack(spacing: 4) {
                            ForEach(group.items) { item in
                                ShoppingWidgetRow(item: item, tint: tint)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                if entry.totalUnchecked > 10 {
                    Text("+\(entry.totalUnchecked - 10) more")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "roost://shopping"))
        }
    }

    private func groupByCategory(_ items: [ShoppingItemDisplay]) -> [(category: String, items: [ShoppingItemDisplay])] {
        let grouped = Dictionary(grouping: items) { item -> String in
            let cat = item.category?.trimmingCharacters(in: .whitespaces)
            return (cat?.isEmpty == false) ? cat! : "Other"
        }
        return grouped
            .sorted { lhs, rhs in
                if lhs.key == "Other" { return false }
                if rhs.key == "Other" { return true }
                return lhs.key < rhs.key
            }
            .map { (category: $0.key, items: $0.value) }
    }
}

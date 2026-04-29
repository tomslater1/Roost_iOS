//
//  ShoppingTripLockScreenView.swift
//  RoostWidgets
//
//  Lock screen / banner presentation for an in-progress shopping trip.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ShoppingTripLockScreenView: View {
    let attributes: ShoppingTripAttributes
    let state: ShoppingTripAttributes.ContentState

    private let tint: Color = .orange

    var body: some View {
        if state.isCompleted {
            completedView
        } else {
            activeView
        }
    }

    private var activeView: some View {
        HStack(alignment: .top, spacing: 14) {
            // LEFT: progress ring + count
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: state.progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(state.checkedCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("of \(state.totalItems)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 52, height: 52)

                if let store = attributes.storeName {
                    Text(store)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // RIGHT: up to 3 next items with toggle, plus footer actions.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                    Text("Shopping Trip")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(attributes.startedAt, style: .timer)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ForEach(state.previewItems.prefix(3)) { item in
                    ShoppingLiveActivityRow(item: item, tint: tint)
                }

                HStack {
                    Link(destination: URL(string: "roost://shopping")!) {
                        Label("Open list", systemImage: "list.bullet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    Button(intent: EndShoppingTripIntent()) {
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }

    private var completedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("All checked off!")
                    .font(.system(size: 14, weight: .semibold))
                if let store = attributes.storeName {
                    Text("at \(store)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "roost://shopping-trip-completed")!) {
                    Label("Log receipt as expense", systemImage: "banknote")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }
}

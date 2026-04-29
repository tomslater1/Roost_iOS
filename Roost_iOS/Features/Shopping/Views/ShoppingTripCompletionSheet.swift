//
//  ShoppingTripCompletionSheet.swift
//  Roost
//
//  Minimal "trip done — log the receipt?" sheet presented when the user
//  ends a Shopping Trip Live Activity. Tapping "Log receipt" currently
//  routes the user into the Expenses tab where they can add the expense
//  manually; a deeper auto-fill into AddExpenseSheet can come later.
//

import SwiftUI

struct ShoppingTripCompletionSheet: View {
    let merchant: String?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.green)
                .padding(.top, 24)

            VStack(spacing: 4) {
                Text("Trip complete!")
                    .font(.system(size: 20, weight: .bold))
                if let merchant {
                    Text("at \(merchant)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Want to log the receipt as a shared expense?")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onDismiss()
                    dismiss()
                    // Send the user to the Expenses tab; the full AddExpense
                    // sheet integration is scoped out of this first pass.
                    if let url = URL(string: "roost://expenses") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Log as expense")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

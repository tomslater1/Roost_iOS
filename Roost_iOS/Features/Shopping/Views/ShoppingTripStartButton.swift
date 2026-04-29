//
//  ShoppingTripStartButton.swift
//  Roost
//
//  Small, reusable "Start / End shopping trip" button.
//  Bound to `ShoppingTripManager.isActive` so the label flips automatically.
//

import SwiftUI

struct ShoppingTripStartButton: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(HomeManager.self) private var homeManager

    @State private var showStorePrompt = false
    @State private var storeName: String = ""

    private var manager: ShoppingTripManager { .shared }

    var body: some View {
        Button {
            if manager.isActive {
                manager.endTrip(reason: .manual)
            } else {
                showStorePrompt = true
            }
        } label: {
            Label(
                manager.isActive ? "End trip" : "Start shopping trip",
                systemImage: manager.isActive ? "stop.circle.fill" : "cart.fill"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(manager.isActive ? .red : .orange)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .alert("Start shopping trip", isPresented: $showStorePrompt) {
            TextField("Store (optional)", text: $storeName)
            Button("Cancel", role: .cancel) { storeName = "" }
            Button("Start") {
                start()
            }
        } message: {
            Text("A Live Activity will show progress on your lock screen.")
        }
    }

    private func start() {
        guard let homeID = homeManager.homeId ?? authManager.homeId,
              let userID = authManager.currentUser?.id else { return }
        manager.startTrip(
            homeID: homeID,
            userID: userID,
            userDisplayName: authManager.currentUser?.displayName,
            storeName: storeName.isEmpty ? nil : storeName
        )
        storeName = ""
    }
}

import SwiftUI

struct IncomeSetupView: View {
    let onComplete: () -> Void

    @Environment(HomeManager.self) private var homeManager
    @Environment(MemberNamesHelper.self) private var memberNames
    @Environment(MoneySettingsViewModel.self) private var settingsVM
    @Environment(ScrambleModeEnvironment.self) private var scramble

    @State private var myIncomeText = ""
    @State private var partnerIncomeText = ""
    @State private var isSaving = false

    private let incomeService = HouseholdIncomeService()
    private var sym: String { settingsVM.settings.currencySymbol }

    private var myAmount: Decimal? { Decimal(string: myIncomeText.replacingOccurrences(of: ",", with: "")) }
    private var partnerAmount: Decimal? { Decimal(string: partnerIncomeText.replacingOccurrences(of: ",", with: "")) }

    private var combinedTotal: Decimal {
        (myAmount ?? 0) + (partnerAmount ?? 0)
    }

    private var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                // Top icon + headline
                Image(systemName: "banknote.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color.roostPrimary.opacity(0.8))
                    .padding(.bottom, 8)

                Text("Your financial picture,\ntogether.")
                    .font(.system(size: 26, weight: .medium))
                    .multilineTextAlignment(.center)

                Text("Roost works best when it knows your combined monthly take-home. Add your income and we'll show you exactly how your household is doing.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // My income field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your monthly take-home pay")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.roostMutedForeground)
                    HStack {
                        Text(sym)
                            .foregroundStyle(Color.roostMutedForeground)
                            .font(.system(size: 20))
                        TextField("e.g. 2,500", text: $myIncomeText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.roostForeground)
                    }
                    .padding(16)
                    .background(Color.roostMuted)
                    .cornerRadius(14)
                }

                // Partner income field
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(memberNames.names.partner)'s monthly take-home pay")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.roostMutedForeground)
                    HStack {
                        Text(sym)
                            .foregroundStyle(Color.roostMutedForeground)
                            .font(.system(size: 20))
                        TextField("e.g. 2,000", text: $partnerIncomeText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.roostForeground)
                    }
                    .padding(16)
                    .background(Color.roostMuted)
                    .cornerRadius(14)
                }

                // Live combined total
                if combinedTotal > 0 {
                    HStack {
                        Text("Combined")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.roostMutedForeground)
                        Spacer()
                        Text(scramble.format(combinedTotal, symbol: sym))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.roostSuccess)
                    }
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.2), value: combinedTotal)
                }

                // Privacy note
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.roostMutedForeground)
                    Text("Your income data stays private in your home. We never share it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.roostMutedForeground)
                }
                .padding(.top, 4)

                // CTA button
                Button {
                    Task { await saveAndComplete() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white) }
                        Text("Set up our finances →")
                    }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(myIncomeText.isEmpty ? Color.roostPrimary.opacity(0.4) : Color.roostPrimary)
                    .cornerRadius(14)
                }
                .disabled(myIncomeText.isEmpty || isSaving)

                // Skip button
                Button("I'll do this later") {
                    // Store a timestamp so we can re-prompt after 7 days
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "roost-income-setup-dismissed-at")
                    onComplete()
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.roostMutedForeground)
                .padding(.top, 4)

                Text("Your partner can add their own income from Settings when they're ready.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.roostMutedForeground)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.roostBackground.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }

    private func saveAndComplete() async {
        guard let homeId = homeManager.homeId,
              let userId = homeManager.currentUserId,
              let myAmount else { return }

        isSaving = true

        // Optimistic patch so downstream screens reflect the value even if
        // the network is down. Replay will reconcile with the server.
        homeManager.patchMemberIncome(userID: userId, amount: myAmount)

        let payload = HouseholdIncomeSetMyIncomePayload(
            userID: userId,
            amount: myAmount,
            homeID: homeId,
            month: startOfMonth
        )
        do {
            try OfflineAwareWrite.enqueue(
                .init(
                    entityType: "household_income",
                    operation: "set_my_income",
                    targetID: userId,
                    homeID: homeId,
                    payload: try JSONEncoder.mutation.encode(payload)
                )
            )
        } catch {
            // Non-fatal — still complete setup
        }
        // Mark as permanently completed (not just snoozed) by storing a far-future timestamp
        UserDefaults.standard.set(Date.distantFuture.timeIntervalSince1970, forKey: "roost-income-setup-dismissed-at")
        isSaving = false
        onComplete()
    }
}

import SwiftUI

struct MoneySettingsView: View {
    @Environment(HomeManager.self) private var homeManager
    @Environment(AuthManager.self) private var authManager
    @Environment(MoneySettingsViewModel.self) private var settingsVM
    @Environment(MemberNamesHelper.self) private var memberNames
    @Environment(ScrambleModeEnvironment.self) private var scramble

    // Income section
    @State private var myIncomeText = ""
    @State private var myIncomeVisible = false
    @State private var partnerIncome: Decimal? = nil
    @State private var householdIncomeTotal: Decimal? = nil
    @State private var incomeSetAt: Date? = nil
    @State private var showSavedConfirmation = false
    @State private var isSavingIncome = false

    // Privacy section
    @State private var scrambleMode = false
    @State private var hideBalances = false

    // Budget preferences section
    @State private var defaultSplit: Double = 50
    @State private var carryForward = "auto"
    @State private var overspendThreshold = 80
    @State private var debounceTask: Task<Void, Never>?

    // Currency section
    @State private var currency = "£"
    @State private var showCurrencyPicker = false

    // Settle up section
    @State private var settlementMode = "separate"
    @State private var paypalHandleText = ""
    @State private var monzoHandleText  = ""
    @State private var isSavingHandles  = false
    @State private var showHandlesSaved = false

    private let incomeService = HouseholdIncomeService()
    private let homeService   = HomeService()
    private var sym: String { currency }

    private var myIncome: Decimal { Decimal(string: myIncomeText.replacingOccurrences(of: ",", with: "")) ?? 0 }
    private var combinedIncome: Decimal {
        if let householdIncomeTotal { return householdIncomeTotal }
        if let partner = partnerIncome { return myIncome + partner }
        return myIncome
    }

    private let currencyOptions: [(String, String)] = [
        ("£", "£ GBP"),
        ("$", "$ USD"),
        ("€", "€ EUR"),
        ("A$", "A$ AUD"),
        ("CA$", "CA$ CAD")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.block) {
                FigmaBackHeader(title: "Money", accent: .roostPrimary)
                incomeCard
                privacyCard
                settleUpCard
                budgetCard
                currencyCard
            }
            .padding(.horizontal, DesignSystem.Spacing.page)
            .padding(.bottom, 108)
            .frame(maxWidth: DesignSystem.Size.maxPhoneWidth)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.roostBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        .task {
            await loadData()
        }
        .confirmationDialog("Currency", isPresented: $showCurrencyPicker) {
            ForEach(currencyOptions, id: \.0) { sym, label in
                Button(label) {
                    currency = sym
                    Task {
                        guard let homeId = homeManager.homeId else { return }
                        try? await settingsVM.updateSetting(\.currencySymbol, value: sym, homeId: homeId)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Income Card

    private var incomeCard: some View {
        RoostCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.inline) {
                    ZStack {
                        Circle()
                            .fill(Color.roostMoneyTint.opacity(0.10))
                            .frame(width: 32, height: 32)
                        Image(systemName: "sterlingsign.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.roostMoneyTint)
                    }
                    Text("Your income")
                        .font(.roostCardTitle)
                        .foregroundStyle(Color.roostForeground)
                }
                .padding(.bottom, DesignSystem.Spacing.row)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Monthly take-home pay")
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostForeground)
                    Text("Only you can see your individual amount. Your combined household income is used across the app.")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
                .padding(.bottom, DesignSystem.Spacing.inline)

                HStack(spacing: 8) {
                    Text(sym)
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostMutedForeground)
                        .frame(width: 20)
                    TextField("e.g. 2500", text: $myIncomeText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.roostForeground)
                        .tint(Color.roostPrimary)
                }
                .padding(.horizontal, DesignSystem.Spacing.card)
                .frame(height: 52)
                .background(Color.roostInput, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                        .strokeBorder(Color.roostHairline, lineWidth: 1)
                )

                if let setAt = incomeSetAt {
                    Text("Last updated \(setAt.formatted(.dateTime.day().month(.wide).year()))")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                        .padding(.top, 6)
                }

                RoostButton(
                    title: showSavedConfirmation ? "Saved" : "Save income",
                    systemImage: showSavedConfirmation ? "checkmark" : nil,
                    isLoading: isSavingIncome
                ) {
                    Task { await saveMyIncome() }
                }
                .disabled(myIncomeText.isEmpty || isSavingIncome)
                .padding(.top, DesignSystem.Spacing.inline)
                .padding(.bottom, 12)

                Divider().overlay(Color.roostHairline)

                HStack(spacing: DesignSystem.Spacing.row) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Share with \(memberNames.names.partner)")
                            .font(.roostBody.weight(.medium))
                            .foregroundStyle(Color.roostForeground)
                        Text("\(memberNames.names.partner) can see your individual amount in their Settings. You can turn this off any time.")
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostMutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $myIncomeVisible)
                        .labelsHidden()
                        .toggleStyle(FigmaSwitchToggleStyle())
                        .onChange(of: myIncomeVisible) { _, newVal in
                            Task { await saveIncomeVisibility(visible: newVal) }
                        }
                }
                .padding(.vertical, 12)

                if myIncomeVisible {
                    Divider().overlay(Color.roostHairline)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(memberNames.names.partner)'s income")
                                .font(.roostBody.weight(.medium))
                                .foregroundStyle(Color.roostForeground)
                            if partnerIncome == nil {
                                Text("\(memberNames.names.partner) hasn't shared their income yet")
                                    .font(.roostCaption)
                                    .foregroundStyle(Color.roostMutedForeground)
                            }
                        }
                        Spacer(minLength: 0)
                        if let partnerInc = partnerIncome {
                            Text(scramble.format(partnerInc, symbol: sym))
                                .font(.roostBody.weight(.semibold))
                                .foregroundStyle(Color.roostForeground)
                        }
                    }
                    .padding(.vertical, 12)
                }

                Divider().overlay(Color.roostHairline)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Combined household")
                            .font(.roostBody.weight(.medium))
                            .foregroundStyle(Color.roostForeground)
                        Text("Used across all Money screens")
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostMutedForeground)
                    }
                    Spacer(minLength: 0)
                    Text(scramble.format(combinedIncome, symbol: sym))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.roostForeground)
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Privacy Card

    private var privacyCard: some View {
        RoostCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.inline) {
                    ZStack {
                        Circle()
                            .fill(Color.roostWarning.opacity(0.10))
                            .frame(width: 32, height: 32)
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.roostWarning)
                    }
                    Text("Privacy & display")
                        .font(.roostCardTitle)
                        .foregroundStyle(Color.roostForeground)
                }
                .padding(.bottom, DesignSystem.Spacing.row)

                HStack(spacing: DesignSystem.Spacing.row) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Scramble mode")
                                .font(.roostBody.weight(.medium))
                                .foregroundStyle(Color.roostForeground)
                            if scrambleMode {
                                Text("On")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.roostWarning)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.roostWarning.opacity(0.12), in: Capsule())
                            }
                        }
                        Text("Replace all amounts with ••• when showing Roost to someone. Syncs to both your devices.")
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostMutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $scrambleMode)
                        .labelsHidden()
                        .toggleStyle(FigmaSwitchToggleStyle())
                        .onChange(of: scrambleMode) { _, _ in
                            Task {
                                guard let homeId = homeManager.homeId else { return }
                                try? await settingsVM.toggleScrambleMode(homeId: homeId)
                            }
                        }
                }
                .padding(.vertical, 12)
                .animation(.roostSnappy, value: scrambleMode)

                Divider().overlay(Color.roostHairline)

                HStack(spacing: DesignSystem.Spacing.row) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hide balances on Money home")
                            .font(.roostBody.weight(.medium))
                            .foregroundStyle(Color.roostForeground)
                        Text("Tap the ring to reveal amounts. Device-only setting.")
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostMutedForeground)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: $hideBalances)
                        .labelsHidden()
                        .toggleStyle(FigmaSwitchToggleStyle())
                        .onChange(of: hideBalances) { _, newVal in
                            UserDefaults.standard.set(newVal, forKey: "roost-hide-balances")
                        }
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        RoostCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.inline) {
                    ZStack {
                        Circle()
                            .fill(Color.roostPrimary.opacity(0.10))
                            .frame(width: 32, height: 32)
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.roostPrimary)
                    }
                    Text("Budget preferences")
                        .font(.roostCardTitle)
                        .foregroundStyle(Color.roostForeground)
                }
                .padding(.bottom, DesignSystem.Spacing.row)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Default expense split")
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostForeground)
                    Text("When you log a shared expense, this is the default split.")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                }
                .padding(.top, 12)
                .padding(.bottom, DesignSystem.Spacing.inline)

                HStack(spacing: DesignSystem.Spacing.inline) {
                    MemberAvatar(label: memberNames.names.meInitials, color: memberNames.names.meColour, size: .xs)
                    Text("\(Int(defaultSplit))%")
                        .font(.roostBody.weight(.semibold))
                        .foregroundStyle(Color.roostForeground)
                        .frame(width: 36)
                    Slider(value: $defaultSplit, in: 0...100, step: 5)
                        .tint(Color.roostPrimary)
                        .onChange(of: defaultSplit) { _, _ in
                            debounceTask?.cancel()
                            debounceTask = Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                guard !Task.isCancelled else { return }
                                guard let homeId = homeManager.homeId else { return }
                                try? await settingsVM.updateSetting(
                                    \.defaultExpenseSplit,
                                    value: defaultSplit,
                                    homeId: homeId
                                )
                            }
                        }
                    Text("\(Int(100 - defaultSplit))%")
                        .font(.roostBody.weight(.semibold))
                        .foregroundStyle(Color.roostForeground)
                        .frame(width: 36)
                    MemberAvatar(label: memberNames.names.partnerInitials, color: memberNames.names.partnerColour, size: .xs)
                }

                if Int(defaultSplit) == 50 {
                    Text("Equal split")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostSuccess)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                }

                Divider().overlay(Color.roostHairline)
                    .padding(.vertical, 12)
                    .animation(.roostSnappy, value: Int(defaultSplit) == 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Budget carry-forward")
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostForeground)
                    Text("When a new month starts, your budget automatically carries forward.")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, DesignSystem.Spacing.inline)

                HStack(spacing: 6) {
                    ForEach([("auto", "Automatic"), ("manual", "Manual")], id: \.0) { value, label in
                        Button {
                            carryForward = value
                            Task {
                                guard let homeId = homeManager.homeId else { return }
                                try? await settingsVM.updateSetting(\.budgetCarryForward, value: value, homeId: homeId)
                            }
                        } label: {
                            Text(label)
                                .font(.roostLabel)
                                .foregroundStyle(carryForward == value ? Color.roostCard : Color.roostMutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    carryForward == value ? Color.roostPrimary : Color.roostInput,
                                    in: RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.roostSnappy, value: carryForward)
                    }
                }

                if carryForward == "manual" {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text("You'll set up your budget each month manually.")
                            .font(.roostCaption)
                    }
                    .foregroundStyle(Color.roostWarning)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider().overlay(Color.roostHairline)
                    .padding(.vertical, 12)
                    .animation(.roostEaseOut, value: carryForward)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Spending alerts")
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostForeground)
                    Text("Alert when an envelope reaches this percentage of its budget.")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                }
                .padding(.bottom, DesignSystem.Spacing.inline)

                HStack(spacing: 6) {
                    ForEach([50, 60, 70, 80, 90], id: \.self) { pct in
                        Button {
                            overspendThreshold = pct
                            Task {
                                guard let homeId = homeManager.homeId else { return }
                                try? await settingsVM.updateSetting(
                                    \.overspendAlertThreshold,
                                    value: pct,
                                    homeId: homeId
                                )
                            }
                        } label: {
                            Text("\(pct)%")
                                .font(.roostLabel)
                                .foregroundStyle(overspendThreshold == pct ? Color.roostCard : Color.roostMutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    overspendThreshold == pct ? Color.roostPrimary : Color.roostInput,
                                    in: RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.roostSnappy, value: overspendThreshold == pct)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Currency Card

    private var currencyCard: some View {
        RoostCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignSystem.Spacing.inline) {
                    ZStack {
                        Circle()
                            .fill(Color.roostSecondary.opacity(0.10))
                            .frame(width: 32, height: 32)
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.roostSecondary)
                    }
                    Text("Currency")
                        .font(.roostCardTitle)
                        .foregroundStyle(Color.roostForeground)
                }
                .padding(.bottom, DesignSystem.Spacing.row)

                Button {
                    showCurrencyPicker = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Display currency")
                                .font(.roostBody.weight(.medium))
                                .foregroundStyle(Color.roostForeground)
                            Text("Used across all Money and Budget screens")
                                .font(.roostCaption)
                                .foregroundStyle(Color.roostMutedForeground)
                        }
                        Spacer(minLength: 0)
                        Text(currencyOptions.first(where: { $0.0 == currency })?.1 ?? currency)
                            .font(.roostLabel)
                            .foregroundStyle(Color.roostPrimary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.roostMutedForeground)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Settle Up Card

    private var settleUpCard: some View {
        RoostCard {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: DesignSystem.Spacing.inline) {
                    ZStack {
                        Circle()
                            .fill(Color.roostMoneyTint.opacity(0.10))
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.roostMoneyTint)
                    }
                    Text("Settle up")
                        .font(.roostCardTitle)
                        .foregroundStyle(Color.roostForeground)
                }
                .padding(.bottom, DesignSystem.Spacing.row)

                // Mode picker
                VStack(alignment: .leading, spacing: 3) {
                    Text("How do you settle up?")
                        .font(.roostBody.weight(.medium))
                        .foregroundStyle(Color.roostForeground)
                    Text("Shared account — settle up is disabled. Separate accounts — payment options appear when settling.")
                        .font(.roostCaption)
                        .foregroundStyle(Color.roostMutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
                .padding(.bottom, DesignSystem.Spacing.inline)

                HStack(spacing: 6) {
                    ForEach([("shared", "Shared account"), ("separate", "Separate accounts")], id: \.0) { value, label in
                        Button {
                            settlementMode = value
                            Task {
                                guard let homeId = homeManager.homeId else { return }
                                try? await settingsVM.updateSetting(\.settlementMode, value: value, homeId: homeId)
                            }
                        } label: {
                            Text(label)
                                .font(.roostLabel)
                                .foregroundStyle(settlementMode == value ? Color.roostCard : Color.roostMutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    settlementMode == value ? Color.roostMoneyTint : Color.roostInput,
                                    in: RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.roostSnappy, value: settlementMode)
                    }
                }

                if settlementMode == "separate" {
                    Divider().overlay(Color.roostHairline)
                        .padding(.top, 16)

                    // PayPal handle
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your PayPal.me username")
                            .font(.roostBody.weight(.medium))
                            .foregroundStyle(Color.roostForeground)
                        Text("Your partner is directed here to pay you.")
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostMutedForeground)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, DesignSystem.Spacing.inline)

                    HStack(spacing: 8) {
                        Text("paypal.me/")
                            .font(.roostBody)
                            .foregroundStyle(Color.roostMutedForeground)
                        TextField("username", text: $paypalHandleText)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.roostBody.weight(.medium))
                            .foregroundStyle(Color.roostForeground)
                            .tint(Color.roostPrimary)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.card)
                    .frame(height: 44)
                    .background(Color.roostInput, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                            .strokeBorder(Color.roostHairline, lineWidth: 1)
                    )

                    Divider().overlay(Color.roostHairline)
                        .padding(.top, 16)

                    // Monzo handle
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your Monzo.me username")
                            .font(.roostBody.weight(.medium))
                            .foregroundStyle(Color.roostForeground)
                        Text("Your partner is directed here to pay you.")
                            .font(.roostCaption)
                            .foregroundStyle(Color.roostMutedForeground)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, DesignSystem.Spacing.inline)

                    HStack(spacing: 8) {
                        Text("monzo.me/")
                            .font(.roostBody)
                            .foregroundStyle(Color.roostMutedForeground)
                        TextField("username", text: $monzoHandleText)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.roostBody.weight(.medium))
                            .foregroundStyle(Color.roostForeground)
                            .tint(Color.roostPrimary)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.card)
                    .frame(height: 44)
                    .background(Color.roostInput, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                            .strokeBorder(Color.roostHairline, lineWidth: 1)
                    )

                    RoostButton(
                        title: showHandlesSaved ? "Saved" : "Save payment handles",
                        systemImage: showHandlesSaved ? "checkmark" : nil,
                        isLoading: isSavingHandles
                    ) {
                        Task { await savePaymentHandles() }
                    }
                    .disabled(isSavingHandles)
                    .padding(.top, DesignSystem.Spacing.inline)
                    .padding(.bottom, 12)
                }
            }
        }
        .animation(.roostEaseOut, value: settlementMode)
    }

    // MARK: - Data loading

    private func savePaymentHandles() async {
        guard let member = homeManager.currentMember else { return }
        isSavingHandles = true
        let paypal = paypalHandleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let monzo  = monzoHandleText.trimmingCharacters(in: .whitespacesAndNewlines)
        try? await homeService.updateMemberPaymentHandles(
            id: member.id,
            paypalUsername: paypal.isEmpty ? nil : paypal,
            monzoUsername:  monzo.isEmpty  ? nil : monzo
        )
        await homeManager.refreshCurrentHome()
        isSavingHandles = false
        withAnimation { showHandlesSaved = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { showHandlesSaved = false }
    }

    private func loadData() async {
        guard let homeId = homeManager.homeId,
              let userId = homeManager.currentUserId else { return }

        if let member = homeManager.currentMember {
            if let income = member.personalIncome {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.minimumFractionDigits = 2
                formatter.maximumFractionDigits = 2
                formatter.decimalSeparator = "."
                myIncomeText = formatter.string(from: income as NSDecimalNumber) ?? "\(income)"
            }
            incomeSetAt = member.incomeSetAt
            myIncomeVisible = member.incomeVisibleToPartner ?? false
        }

        async let total = incomeService.fetchCombinedMemberIncome(homeId: homeId)
        async let partner = incomeService.fetchPartnerIncome(homeId: homeId, currentUserId: userId)
        householdIncomeTotal = try? await total
        partnerIncome = try? await partner

        defaultSplit = settingsVM.settings.defaultExpenseSplit
        carryForward = settingsVM.settings.budgetCarryForward
        overspendThreshold = settingsVM.settings.overspendAlertThreshold
        currency = settingsVM.settings.currencySymbol
        scrambleMode = settingsVM.settings.scrambleMode
        hideBalances = UserDefaults.standard.bool(forKey: "roost-hide-balances")
        settlementMode = settingsVM.settings.settlementMode
        if let member = homeManager.currentMember {
            paypalHandleText = member.paypalUsername ?? ""
            monzoHandleText  = member.monzoUsername  ?? ""
        }
    }

    private func saveMyIncome() async {
        guard let homeId = homeManager.homeId,
              let userId = homeManager.currentUserId else { return }
        let cleaned = myIncomeText.replacingOccurrences(of: sym, with: "").replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: cleaned) else { return }

        isSavingIncome = true
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()

        // Optimistic in-memory patch — UI updates immediately; a follow-up
        // refreshCurrentHome() will reconcile once the mutation replays.
        homeManager.patchMemberIncome(userID: userId, amount: amount)
        incomeSetAt = homeManager.currentMember?.incomeSetAt

        // Recompute combined total locally so the "household income" row
        // reflects the new value offline. `fetchCombinedMemberIncome` would
        // fail offline; compute from cached members instead.
        householdIncomeTotal = homeManager.members.reduce(Decimal(0)) { total, member in
            total + (member.personalIncome ?? 0)
        }

        let payload = HouseholdIncomeSetMyIncomePayload(
            userID: userId,
            amount: amount,
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
            withAnimation { showSavedConfirmation = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSavedConfirmation = false }
        } catch {
            // Enqueue failure (out of disk space etc.) — leave UI state
            // reflecting the optimistic value; user will see the real state
            // on next refresh.
        }
        isSavingIncome = false
    }

    private func saveIncomeVisibility(visible: Bool) async {
        guard let homeId = homeManager.homeId,
              let userId = homeManager.currentUserId else { return }

        // Optimistic patch of in-memory state.
        homeManager.patchMemberIncomeVisibility(userID: userId, visible: visible)

        let payload = HouseholdIncomeSetVisibilityPayload(
            userID: userId,
            visible: visible,
            homeID: homeId
        )

        do {
            try OfflineAwareWrite.enqueue(
                .init(
                    entityType: "household_income",
                    operation: "set_visibility",
                    targetID: userId,
                    homeID: homeId,
                    payload: try JSONEncoder.mutation.encode(payload)
                )
            )
        } catch {
            // Silently ignore — user will see corrected state on next refresh.
        }

        // Partner income visibility depends on BOTH partners' flags — only
        // fetch when online; stale value is acceptable otherwise.
        partnerIncome = try? await incomeService.fetchPartnerIncome(homeId: homeId, currentUserId: userId)
    }
}

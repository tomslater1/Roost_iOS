import Charts
import SwiftUI

// MARK: - MoneyOverviewView

struct MoneyOverviewView: View {

    @Environment(HomeManager.self) private var homeManager
    @Environment(ExpensesViewModel.self) private var expensesVM
    @Environment(BudgetTemplateViewModel.self) private var budgetVM
    @Environment(MonthlyMoneyViewModel.self) private var summaryVM
    @Environment(MoneySettingsViewModel.self) private var settingsVM
    @Environment(ScrambleModeEnvironment.self) private var scramble
    @Environment(HazelViewModel.self) private var hazelVM

    @State private var arcProgress: CGFloat = 0
    @State private var showHistoryUpsell = false
    @State private var showInsightsUpsell = false
    @State private var pastBillsExpanded = false

    // Hazel Budget Insights (Pro)
    @State private var hazelInsight: HazelBudgetInsight?
    @State private var hazelInsightLoading = false
    @ObservationIgnored private let insightsService = BudgetInsightsService()

    // MARK: - Derived helpers

    private var isFreeTier: Bool { !(homeManager.home?.hasProAccess ?? false) }
    private var sym: String { settingsVM.settings.currencySymbol }
    private var isLoading: Bool { summaryVM.isLoading || budgetVM.isLoading }
    private var currentMonth: Date { summaryVM.selectedMonth }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    private var thisMonthExpenses: [ExpenseWithSplits] {
        let cal = Calendar.current
        return expensesVM.expenses.filter { ews in
            guard let date = ews.incurredOnDate else { return false }
            return cal.isDate(date, equalTo: currentMonth, toGranularity: .month)
        }
    }

    private var thisMonthExpensesAsExpense: [Expense] {
        thisMonthExpenses.map(\.expense)
    }

    private var pctSpentProgress: CGFloat {
        guard let summary = summaryVM.summary, summary.hasIncome else { return 0 }
        return CGFloat(min(max(NSDecimalNumber(decimal: summary.pctSpent).doubleValue / 100.0, 0), 1))
    }

    private var arcColour: Color {
        let p = pctSpentProgress
        if p > 1 { return Color(hex: 0xC75146) }
        if p > 0.8 { return Color(hex: 0xE6A563) }
        return Color(hex: 0x9DB19F)
    }

    private var healthScore: Int {
        guard let summary = summaryVM.summary, summary.hasIncome else { return 50 }
        return budgetVM.calculateHealthScore(income: summary.income, hasGoals: false)
    }

    // MARK: - Budget status items

    private struct BudgetStatusItem: Identifiable {
        let id: UUID
        let name: String
        let colour: Color
        let spent: Decimal
        let effective: Decimal

        var isOverspent: Bool { effective > 0 && spent > effective }

        var fillRatio: Double {
            guard effective > 0 else { return spent > 0 ? 1.0 : 0 }
            return min(NSDecimalNumber(decimal: spent / effective).doubleValue, 1.0)
        }
    }

    private var budgetStatusItems: [BudgetStatusItem] {
        let expenses = thisMonthExpensesAsExpense
        let items = budgetVM.lifestyleLines.map { line -> BudgetStatusItem in
            let colour = budgetVM.categories
                .first { $0.name.caseInsensitiveCompare(line.name) == .orderedSame }?.colour
                ?? categoryColour(for: line.name)
            let spent = budgetVM.getSpent(category: line.name, month: currentMonth, expenses: expenses)
            let effective = budgetVM.getEffectiveAmount(lineId: line.id, month: currentMonth)
            return BudgetStatusItem(id: line.id, name: line.name, colour: colour, spent: spent, effective: effective)
        }
        return items.sorted {
            if $0.isOverspent != $1.isOverspent { return $0.isOverspent }
            return $0.spent > $1.spent
        }
    }

    // MARK: - Spending trend

    private struct MonthDataPoint: Identifiable {
        let id = UUID()
        let month: Date
        let total: Decimal
        var label: String {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM"
            return fmt.string(from: month)
        }
    }

    private var sixMonthSpend: [MonthDataPoint] {
        let cal = Calendar.current
        let todayStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        var result: [MonthDataPoint] = []
        for i in (0..<6).reversed() {
            guard let m = cal.date(byAdding: .month, value: -i, to: todayStart) else { continue }
            let total = expensesVM.expenses
                .filter { ews in
                    guard let d = ews.incurredOnDate else { return false }
                    return cal.isDate(d, equalTo: m, toGranularity: .month)
                }
                .reduce(Decimal(0)) { $0 + $1.amount }
            result.append(MonthDataPoint(month: m, total: total))
        }
        return result
    }

    // MARK: - Month comparison

    private struct CategoryComparison: Identifiable {
        let id = UUID()
        let name: String
        let colour: Color
        let thisMonth: Decimal
        let lastMonth: Decimal

        var changePct: Double {
            guard lastMonth > 0 else { return thisMonth > 0 ? 1.0 : 0 }
            return NSDecimalNumber(decimal: (thisMonth - lastMonth) / lastMonth).doubleValue
        }
    }

    private var previousMonth: Date? {
        Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)
    }

    private var categoryComparison: [CategoryComparison] {
        guard let prev = previousMonth else { return [] }
        let cal = Calendar.current
        let prevExpenses: [Expense] = expensesVM.expenses
            .filter { ews in
                guard let d = ews.incurredOnDate else { return false }
                return cal.isDate(d, equalTo: prev, toGranularity: .month)
            }
            .map(\.expense)
        let thisExpenses = thisMonthExpensesAsExpense

        return budgetVM.categories
            .map { cat -> CategoryComparison in
                let thisSpent = budgetVM.getSpent(category: cat.name, month: currentMonth, expenses: thisExpenses)
                let prevSpent = budgetVM.getSpent(category: cat.name, month: prev, expenses: prevExpenses)
                return CategoryComparison(name: cat.name, colour: cat.colour, thisMonth: thisSpent, lastMonth: prevSpent)
            }
            .filter { $0.thisMonth > 0 || $0.lastMonth > 0 }
            .sorted { $0.thisMonth > $1.thisMonth }
    }

    private var overallChangePct: Double? {
        let comp = categoryComparison
        guard !comp.isEmpty else { return nil }
        let thisTotal = comp.reduce(Decimal(0)) { $0 + $1.thisMonth }
        let lastTotal = comp.reduce(Decimal(0)) { $0 + $1.lastMonth }
        guard lastTotal > 0 else { return nil }
        return NSDecimalNumber(decimal: (thisTotal - lastTotal) / lastTotal).doubleValue
    }

    private var biggestMover: CategoryComparison? {
        categoryComparison.max { abs($0.changePct) < abs($1.changePct) }
    }

    // MARK: - Bills

    private var upcomingBills: [BudgetTemplateLine] {
        let today = Calendar.current.component(.day, from: Date())
        return budgetVM.fixedLines
            .filter { ($0.dayOfMonth ?? 0) >= today }
            .sorted { ($0.dayOfMonth ?? 0) < ($1.dayOfMonth ?? 0) }
    }

    private var pastBills: [BudgetTemplateLine] {
        let today = Calendar.current.component(.day, from: Date())
        return budgetVM.fixedLines
            .filter { ($0.dayOfMonth ?? 0) < today }
            .sorted { ($0.dayOfMonth ?? 0) < ($1.dayOfMonth ?? 0) }
    }

    // MARK: - Budget insight

    private var budgetInsight: String? {
        guard let summary = summaryVM.summary, !isLoading else { return nil }
        let expenses = thisMonthExpensesAsExpense

        // 1. Overspent envelope
        if let line = budgetVM.lifestyleLines.first(where: { line in
            let spent = budgetVM.getSpent(category: line.name, month: currentMonth, expenses: expenses)
            let effective = budgetVM.getEffectiveAmount(lineId: line.id, month: currentMonth)
            return effective > 0 && spent > effective
        }) {
            let spent = budgetVM.getSpent(category: line.name, month: currentMonth, expenses: expenses)
            let effective = budgetVM.getEffectiveAmount(lineId: line.id, month: currentMonth)
            return "\(line.name) is \(sym)\(compact(spent - effective)) over budget this month. Consider reviewing your \(line.name.lowercased()) spend."
        }

        // 2. Projected overspend
        if let projected = summaryVM.projectedSurplus, projected < 0 {
            return "At your current pace, you're on track to overspend by \(sym)\(compact(abs(projected))) this month."
        }

        // 3. Projected surplus
        if let projected = summaryVM.projectedSurplus, projected > 100 {
            let daysLeft = summaryVM.daysInMonth - summaryVM.daysElapsed
            return "You're on track for a \(sym)\(compact(projected)) surplus — \(daysLeft) days to go."
        }

        // 4. Budget coverage
        if summary.hasIncome {
            let pct = Int(NSDecimalNumber(decimal: summary.pctSpent).doubleValue)
            let daysLeft = summaryVM.daysInMonth - summaryVM.daysElapsed
            return "You've used \(pct)% of your income so far, with \(daysLeft) days remaining this month."
        }

        // 5. Default
        return "Set your income to unlock personalised monthly insights."
    }

    // MARK: - Hazel Insights

    private var monthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: currentMonth)
    }

    private var monthKeyForInsights: String {
        "\(homeManager.homeId?.uuidString ?? "")-\(monthLabel)"
    }

    private var hazelInsightInput: HazelBudgetInsightInput? {
        guard let summary = summaryVM.summary else { return nil }

        let expenses = thisMonthExpensesAsExpense
        let topCats: [HazelBudgetInsightInput.TopCategory] = budgetVM.lifestyleLines
            .compactMap { line -> HazelBudgetInsightInput.TopCategory? in
                let spend = NSDecimalNumber(decimal: budgetVM.getSpent(category: line.name, month: currentMonth, expenses: expenses)).doubleValue
                guard spend > 0 else { return nil }
                let limit = NSDecimalNumber(decimal: budgetVM.getEffectiveAmount(lineId: line.id, month: currentMonth)).doubleValue
                let total = NSDecimalNumber(decimal: summary.actualSpend).doubleValue
                let pct = total > 0 ? (spend / total) * 100 : 0
                return HazelBudgetInsightInput.TopCategory(
                    name: line.name,
                    spend: spend,
                    limit: limit > 0 ? limit : nil,
                    pct: pct,
                    recurringTotal: 0
                )
            }
            .sorted { $0.spend > $1.spend }
            .prefix(5)
            .map { $0 }

        let totalSpent = NSDecimalNumber(decimal: summary.actualSpend).doubleValue
        let totalBudget = NSDecimalNumber(decimal: summary.totalBudgeted).doubleValue
        let projected = NSDecimalNumber(decimal: summary.projectedTotal).doubleValue
        let income = NSDecimalNumber(decimal: summary.income).doubleValue
        let remaining = max(0, income - totalSpent)
        let overspend = totalBudget > 0 ? max(0, totalSpent - totalBudget) : 0

        return HazelBudgetInsightInput(
            monthLabel: monthLabel,
            totalSpent: totalSpent,
            totalBudget: totalBudget,
            projectedMonthEnd: projected,
            remaining: remaining,
            overspend: overspend,
            topCategories: topCats
        )
    }

    private func fetchHazelInsight() async {
        guard !isFreeTier, hazelVM.insightsEnabled,
              let homeId = homeManager.homeId,
              let input = hazelInsightInput else { return }

        if let cached = insightsService.cachedInsight(for: monthLabel) {
            hazelInsight = cached
            return
        }

        hazelInsightLoading = true
        defer { hazelInsightLoading = false }

        if let result = try? await insightsService.fetchInsights(homeId: homeId, input: input) {
            hazelInsight = result
            insightsService.cache(result, for: monthLabel)
        }
    }

    // MARK: - Helpers

    private func compact(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }

    private func categoryColour(for name: String) -> Color {
        moneyColour(for: name)
    }

    private func billDateLabel(day: Int) -> String {
        let today = Calendar.current.component(.day, from: Date())
        if day == today { return "Today" }
        if day == today + 1 { return "Tomorrow" }
        let suffix: String
        switch day % 10 {
        case 1 where day != 11: suffix = "st"
        case 2 where day != 12: suffix = "nd"
        case 3 where day != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    private func updateArcProgress() {
        withAnimation(.easeOut(duration: 0.8)) {
            arcProgress = pctSpentProgress
        }
    }

    private func reloadSummary() {
        Task {
            guard let homeId = homeManager.homeId else { return }
            await summaryVM.loadSummary(homeId: homeId)
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.md) {

                FigmaBackHeader(title: "Overview", accent: .roostMoneyTint)
                    .padding(.horizontal, DesignSystem.Spacing.page)

                monthNavigator
                    .padding(.horizontal, DesignSystem.Spacing.page)

                VStack(alignment: .leading, spacing: 12) {

                    // Zone 1 — Ring + stats + budget insight
                    zone1RingCard

                    // Zone 2 — Money flow
                    zone2MoneyFlow

                    // Zone 3 — Budget status per lifestyle line
                    if !budgetVM.lifestyleLines.isEmpty || isLoading {
                        zone3BudgetStatus
                    }

                    // Zone 4 — Upcoming bills
                    if !budgetVM.fixedLines.isEmpty {
                        zone4ComingUp
                    }

                    // Zone 5 — Spending trend (Swift Charts)
                    zone5SpendingTrend

                    // Zone 6 — Month comparison
                    zone6MonthComparison

                    // Bottom: income update link
                    incomeUpdateLink
                }
                .padding(.horizontal, DesignSystem.Spacing.page)
            }
            .padding(.bottom, DesignSystem.Spacing.screenBottom + 4)
        }
        .background(Color.roostBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBackEnabled()
        .task(id: homeManager.homeId) {
            guard let homeId = homeManager.homeId else { return }
            await summaryVM.loadSummary(homeId: homeId)
            updateArcProgress()
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                updateArcProgress()
            }
        }
        .onChange(of: summaryVM.isLoading) { _, loading in
            if !loading { updateArcProgress() }
        }
        .nestUpsell(isPresented: $showHistoryUpsell, feature: .budgetHistory)
        .nestUpsell(isPresented: $showInsightsUpsell, feature: .budgetInsights)
        .task(id: monthKeyForInsights) {
            // Reset cached insight when month changes, then fetch fresh
            hazelInsight = insightsService.cachedInsight(for: monthLabel)
            await fetchHazelInsight()
        }
    }
}

// MARK: - Month navigator

private extension MoneyOverviewView {

    var monthNavigator: some View {
        MonthNavigator(
            label: monthTitle,
            onPrevious: { summaryVM.navigateMonth(direction: -1); reloadSummary() },
            onNext: { summaryVM.navigateMonth(direction: 1); reloadSummary() },
            canGoNext: !isCurrentMonth,
            isPro: !isFreeTier,
            onProGate: { showHistoryUpsell = true }
        )
    }

    var monthTitle: String {
        if isCurrentMonth { return "This month" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: currentMonth)
    }
}

// MARK: - Zone 1: Ring card

private extension MoneyOverviewView {

    var zone1RingCard: some View {
        RoostCard(padding: 12, prominence: .quiet) {
            if let error = summaryVM.error, summaryVM.summary == nil {
                errorState(error: error)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 14) {
                        ringArc104
                        zone1Stats
                    }
                    if let insight = budgetInsight {
                        Text(insight)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.roostMutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    } else if isLoading {
                        Text("Loading spending pace.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.roostMutedForeground)
                            .redacted(reason: .placeholder)
                    }
                }
            }
        }
    }

    var ringArc104: some View {
        ZStack {
            Circle()
                .stroke(Color.roostMuted.opacity(0.65), lineWidth: 8)
                .frame(width: 104, height: 104)

            Circle()
                .trim(from: 0, to: arcProgress)
                .stroke(arcColour, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 104, height: 104)
                .animation(.easeOut(duration: 0.8), value: arcProgress)

            if isLoading {
                loadingPulse
            } else if let summary = summaryVM.summary, summary.hasIncome {
                VStack(spacing: 2) {
                    Text("\(Int(NSDecimalNumber(decimal: summary.pctSpent).doubleValue))%")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.roostForeground)
                    Text("spent")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.roostMutedForeground)
                }
            } else {
                VStack(spacing: 2) {
                    Text("Set")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.roostMoneyTint)
                    Text("income")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.roostMoneyTint)
                }
            }
        }
        .frame(width: 104, height: 104)
    }

    var loadingPulse: some View {
        ZStack {
            Circle()
                .fill(Color.roostMuted.opacity(0.55))
                .frame(width: 34, height: 34)
            Circle()
                .stroke(Color.roostMutedForeground.opacity(0.18), lineWidth: 5)
                .frame(width: 52, height: 52)
        }
        .redacted(reason: .placeholder)
    }

    var zone1Stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Income")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.roostMutedForeground)
                if isLoading {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.roostMutedForeground.opacity(0.15))
                        .frame(width: 70, height: 14)
                } else if let s = summaryVM.summary, s.hasIncome {
                    Text(scramble.format(s.income, symbol: sym))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.roostForeground)
                } else {
                    Text("Not set")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.roostMoneyTint)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Budgeted")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.roostMutedForeground)
                if isLoading {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.roostMutedForeground.opacity(0.15))
                        .frame(width: 80, height: 14)
                } else if let s = summaryVM.summary, s.hasIncome {
                    let pct = Int(NSDecimalNumber(decimal: s.pctOfIncomeBudgeted).doubleValue)
                    Text("\(pct)% of income")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.roostForeground)
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.roostMutedForeground)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Health")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.roostMutedForeground)
                let score = isLoading ? 50 : healthScore
                let scoreColour: Color = score >= 70 ? Color.roostSecondary
                    : score >= 40 ? Color.roostWarning
                    : Color.roostDestructive
                Text(isLoading ? "—" : "\(score) / 100")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isLoading ? Color.roostMutedForeground : scoreColour)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func errorState(error: Error) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.roostMoneyTint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't load summary")
                    .font(.roostCardTitle)
                    .foregroundStyle(Color.roostForeground)
                Button("Try again") {
                    reloadSummary()
                }
                .font(.roostCaption)
                .foregroundStyle(Color.roostMoneyTint)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Zone 2: Money flow

private extension MoneyOverviewView {

    var zone2MoneyFlow: some View {
        VStack(alignment: .leading, spacing: 7) {
            eyebrow("MONEY FLOW")

            RoostCard(padding: 12, prominence: .quiet) {
                VStack(alignment: .leading, spacing: 10) {
                    let income = summaryVM.summary?.income ?? 0
                    let fixed = summaryVM.summary?.fixedCosts ?? budgetVM.totalFixed
                    let lifestyle = summaryVM.summary?.envelopesTotal ?? budgetVM.totalLifestyle
                    let surplus = income > 0 ? income - fixed - lifestyle : nil

                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.roostSecondary)
                            .font(.system(size: 13))
                        Text("Monthly income")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.roostMutedForeground)
                        Spacer()
                        if income > 0 {
                            Text(scramble.format(income, symbol: sym))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.roostForeground)
                        } else {
                            Text("Not set")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.roostMoneyTint)
                        }
                    }

                    moneyHairline

                    flowBarRow(icon: "lock.fill", iconColour: Color.roostMoneyTint,
                               label: "Fixed costs", amount: fixed, income: income,
                               fillColour: Color.roostMoneyTint)

                    flowBarRow(icon: "cart.fill", iconColour: Color.roostWarning,
                               label: "Lifestyle", amount: lifestyle, income: income,
                               fillColour: Color.roostWarning)

                    if let surplus {
                        moneyHairline
                        HStack {
                            Image(systemName: surplus >= 0 ? "arrow.up.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(surplus >= 0 ? Color.roostSecondary : Color.roostDestructive)
                                .font(.system(size: 13))
                            Text("Est. unallocated")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.roostMutedForeground)
                            Spacer()
                            Text(scramble.format(surplus, symbol: sym))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(surplus >= 0 ? Color.roostSecondary : Color.roostDestructive)
                        }
                    }
                }
            }
        }
    }

    func flowBarRow(icon: String, iconColour: Color, label: String,
                    amount: Decimal, income: Decimal, fillColour: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColour)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.roostMutedForeground)
                Spacer()
                Text(scramble.format(amount, symbol: sym))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.roostForeground)
            }
            GeometryReader { geo in
                let ratio: Double = income > 0
                    ? min(NSDecimalNumber(decimal: amount / income).doubleValue, 1.0)
                    : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(fillColour.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(fillColour)
                        .frame(width: geo.size.width * ratio, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Zone 3: Budget status

private extension MoneyOverviewView {

    var zone3BudgetStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            eyebrow("BUDGET THIS MONTH")

            RoostCard(padding: 12, prominence: .quiet) {
                VStack(alignment: .leading, spacing: 10) {
                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in skeletonBudgetRow }
                    } else {
                        let items = budgetStatusItems
                        if items.isEmpty {
                            Text("No lifestyle budget lines set up yet.")
                                .font(.roostBody)
                                .foregroundStyle(Color.roostMutedForeground)
                        } else {
                            ForEach(items) { item in
                                budgetStatusRow(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func budgetStatusRow(item: BudgetStatusItem) -> some View {
        let barColour: Color = item.isOverspent ? Color(hex: 0xC75146)
            : item.fillRatio > 0.8 ? Color(hex: 0xE6A563)
            : item.colour

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle()
                    .fill(item.colour)
                    .frame(width: 7, height: 7)
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.roostForeground)
                Spacer()
                if item.isOverspent {
                    Text("Over \(sym)\(compact(item.spent - item.effective))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: 0xC75146))
                } else if item.effective > 0 {
                    Text("\(scramble.format(item.effective - item.spent, symbol: sym)) left")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.roostMutedForeground)
                } else {
                    Text(scramble.format(item.spent, symbol: sym))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.roostMutedForeground)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(barColour.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(barColour)
                        .frame(width: geo.size.width * item.fillRatio, height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    var skeletonBudgetRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Color.roostMutedForeground.opacity(0.2))
                    .frame(width: 8, height: 8)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.roostMutedForeground.opacity(0.15))
                    .frame(width: 80, height: 12)
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.roostMutedForeground.opacity(0.15))
                    .frame(width: 50, height: 12)
            }
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.roostMutedForeground.opacity(0.1))
                .frame(height: 5)
        }
    }
}

// MARK: - Zone 4: Coming up

private extension MoneyOverviewView {

    var zone4ComingUp: some View {
        VStack(alignment: .leading, spacing: 7) {
            eyebrow("COMING UP")

            RoostCard(padding: 12, prominence: .quiet) {
                VStack(alignment: .leading, spacing: 0) {
                    let upcoming = upcomingBills
                    let past = pastBills

                    if upcoming.isEmpty && past.isEmpty {
                        Text("No fixed costs set up.")
                            .font(.roostBody)
                            .foregroundStyle(Color.roostMutedForeground)
                    } else {
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, bill in
                            if index > 0 { moneyHairline.padding(.vertical, 6) }
                            billRow(bill: bill, isDueSoon: billIsDueSoon(bill))
                        }

                        if !past.isEmpty {
                            if !upcoming.isEmpty { moneyHairline.padding(.vertical, 6) }
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    pastBillsExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(past.count) paid this month")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.roostMutedForeground)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color.roostMutedForeground)
                                        .rotationEffect(.degrees(pastBillsExpanded ? 180 : 0))
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if pastBillsExpanded {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(past.enumerated()), id: \.element.id) { index, bill in
                                        if index > 0 { moneyHairline.padding(.vertical, 6) }
                                        billRow(bill: bill, isDueSoon: false)
                                            .opacity(0.55)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                }
            }
        }
    }

    func billIsDueSoon(_ bill: BudgetTemplateLine) -> Bool {
        guard let day = bill.dayOfMonth else { return false }
        let today = Calendar.current.component(.day, from: Date())
        return day >= today && day <= today + 3
    }

    @ViewBuilder
    func billRow(bill: BudgetTemplateLine, isDueSoon: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.roostForeground)
                if let day = bill.dayOfMonth {
                    Text(billDateLabel(day: day))
                        .font(.system(size: 11))
                        .foregroundStyle(isDueSoon ? Color.roostMoneyTint : Color.roostMutedForeground)
                }
            }
            Spacer()
            Text(scramble.format(bill.displayAmount, symbol: sym))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.roostForeground)
        }
        .padding(isDueSoon ? 8 : 0)
        .background(isDueSoon ? Color.roostWarning.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            Group {
                if isDueSoon {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.roostWarning.opacity(0.34), lineWidth: 1)
                }
            }
        )
    }
}

// MARK: - Zone 5: Spending trend

private extension MoneyOverviewView {

    var zone5SpendingTrend: some View {
        VStack(alignment: .leading, spacing: 7) {
            eyebrow("SPENDING TREND")

            RoostCard(padding: 12, prominence: .quiet) {
                VStack(alignment: .leading, spacing: 10) {
                    let allData = sixMonthSpend
                    let chartData = isFreeTier ? Array(allData.suffix(1)) : allData

                    if allData.allSatisfy({ $0.total == 0 }) {
                        Text("No spending data yet.")
                            .font(.roostBody)
                            .foregroundStyle(Color.roostMutedForeground)
                    } else {
                        Chart {
                            ForEach(chartData) { point in
                                BarMark(
                                    x: .value("Month", point.label),
                                    y: .value("Spend", NSDecimalNumber(decimal: point.total).doubleValue)
                                )
                                .foregroundStyle(Color.roostSecondary)
                                .cornerRadius(3)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(sym)\(Int(v))")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(Color.roostMutedForeground)
                                    }
                                }
                                AxisGridLine()
                                    .foregroundStyle(Color.roostMutedForeground.opacity(0.1))
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    Text(value.as(String.self) ?? "")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color.roostMutedForeground)
                                }
                            }
                        }
                        .frame(height: 116)

                        if isFreeTier {
                            Button {
                                showHistoryUpsell = true
                            } label: {
                                Text("See 6-month history with Roost Pro →")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.roostMoneyTint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Zone 6: Month comparison

private extension MoneyOverviewView {

    var zone6MonthComparison: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                eyebrow("MONTH COMPARISON")
                Spacer()
                if !isFreeTier, let pct = overallChangePct {
                    let increased = pct > 0
                    Text("\(increased ? "+" : "")\(Int(pct * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(increased ? Color(hex: 0xC75146) : Color(hex: 0x9DB19F))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (increased ? Color(hex: 0xC75146) : Color(hex: 0x9DB19F)).opacity(0.12)
                        )
                        .clipShape(Capsule())
                }
            }

            if isFreeTier {
                Button {
                    showInsightsUpsell = true
                } label: {
                    RoostCard(padding: 12, prominence: .quiet) {
                        HStack(spacing: 10) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.roostMoneyTint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Month comparison")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.roostForeground)
                                Text("See how this month compares to last with Roost Pro.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.roostMutedForeground)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.roostMutedForeground)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                RoostCard(padding: 12, prominence: .quiet) {
                    VStack(alignment: .leading, spacing: 10) {
                        let comp = categoryComparison

                        if comp.isEmpty {
                            Text("No comparison data yet. Add expenses to see how this month compares to last.")
                                .font(.roostBody)
                                .foregroundStyle(Color.roostMutedForeground)
                        } else {
                            // Biggest mover callout
                            if let mover = biggestMover, abs(mover.changePct) > 0.05 {
                                let up = mover.changePct > 0
                                HStack(spacing: 6) {
                                    Image(systemName: up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                        .foregroundStyle(up ? Color.roostDestructive : Color.roostSecondary)
                                        .font(.system(size: 12))
                                    Text("\(mover.name) \(up ? "up" : "down") \(Int(abs(mover.changePct) * 100))% vs last month")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.roostMutedForeground)
                                }
                                .padding(.bottom, 2)
                            }

                            // Per-category comparison rows
                            ForEach(comp.prefix(5)) { item in
                                comparisonRow(item: item)
                            }

                            // Legend
                            HStack(spacing: Spacing.lg) {
                                legendDot(colour: Color.roostForeground.opacity(0.6), label: "This month")
                                legendDot(colour: Color.roostMutedForeground.opacity(0.4), label: "Last month")
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private func comparisonRow(item: CategoryComparison) -> some View {
        let maxAmount = max(item.thisMonth, item.lastMonth, 1)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle()
                    .fill(item.colour)
                    .frame(width: 7, height: 7)
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.roostForeground)
                Spacer()
                Text(scramble.format(item.thisMonth, symbol: sym))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.roostForeground)
            }
            GeometryReader { geo in
                let thisRatio = min(NSDecimalNumber(decimal: item.thisMonth / maxAmount).doubleValue, 1.0)
                let lastRatio = min(NSDecimalNumber(decimal: item.lastMonth / maxAmount).doubleValue, 1.0)
                VStack(spacing: 2) {
                    // This month bar
                    ZStack(alignment: .leading) {
                        Capsule().fill(item.colour.opacity(0.1)).frame(height: 4)
                        Capsule().fill(item.colour).frame(width: geo.size.width * thisRatio, height: 4)
                    }
                    // Last month bar
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.roostMutedForeground.opacity(0.1)).frame(height: 4)
                        Capsule().fill(Color.roostMutedForeground.opacity(0.35)).frame(width: geo.size.width * lastRatio, height: 4)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    func legendDot(colour: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(colour)
                .frame(width: 14, height: 4)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.roostMutedForeground)
        }
    }
}

// MARK: - Income update link + shared helpers

private extension MoneyOverviewView {

    var incomeUpdateLink: some View {
        HStack {
            Spacer()
            NavigationLink {
                Text("Income settings coming soon.")
                    .foregroundStyle(Color.roostMutedForeground)
                    .navigationTitle("Income")
            } label: {
                Text("Update your income in Settings →")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.roostMutedForeground)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, Spacing.sm)
    }

    func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Color.roostMutedForeground)
    }

    var moneyHairline: some View {
        Rectangle()
            .fill(Color.roostHairline)
            .frame(height: 1)
            .opacity(0.72)
    }
}

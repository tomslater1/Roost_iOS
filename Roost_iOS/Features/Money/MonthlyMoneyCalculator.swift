import Foundation

// MARK: - MonthlyMoneyCalculator
//
// Local fallback for `MonthlyMoneyService.fetchMonthlySummary`. When the
// server RPC is unreachable (offline), this recomputes a `MonthlySummary`
// from whatever cached/in-memory data the app already has:
//
//   - income:        sum of `home_members.personal_income`
//   - actualSpend:   sum of cached expense amounts for the given month
//   - totalBudgeted: sum of cached `budgets` amounts for the given month
//   - fixedCosts:    0 (the server splits fixed vs envelopes via the budget
//                    template domain which isn't cached yet; the server
//                    value will reconcile on next online refresh)
//   - envelopesTotal: same as `totalBudgeted` for now
//   - surplus:       income − totalBudgeted
//   - projectedTotal: daily-rate projection × days in month
//   - pctOfIncomeBudgeted / pctSpent: straight ratios (0 when income is 0)
//
// The calculator is intentionally coarse. Online, the server RPC is always
// authoritative; this only keeps the Money screen readable when the network
// is down so the user sees something close to reality.

@MainActor
enum MonthlyMoneyCalculator {
    static func compute(
        members: [HomeMember],
        expenses: [ExpenseWithSplits],
        budgets: [Budget],
        month: Date,
        calendar: Calendar = .current,
        today: Date = Date()
    ) -> MonthlySummary {
        let income = members.reduce(Decimal(0)) { $0 + ($1.personalIncome ?? 0) }

        let actualSpend = expenses
            .filter { ews in
                guard let d = ews.incurredOnDate else { return false }
                return calendar.isDate(d, equalTo: month, toGranularity: .month)
            }
            .reduce(Decimal(0)) { $0 + $1.amount }

        let totalBudgeted = budgets
            .filter { calendar.isDate($0.month, equalTo: month, toGranularity: .month) }
            .reduce(Decimal(0)) { $0 + $1.amount }

        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let daysElapsed: Int = {
            if calendar.isDate(today, equalTo: month, toGranularity: .month) {
                return max(calendar.component(.day, from: today), 1)
            }
            return daysInMonth
        }()
        let dailyRate: Decimal = daysElapsed > 0 ? actualSpend / Decimal(daysElapsed) : 0
        let projectedTotal = dailyRate * Decimal(daysInMonth)

        let pctOfIncomeBudgeted: Decimal = income > 0 ? (totalBudgeted / income) * 100 : 0
        let pctSpent: Decimal = income > 0 ? (actualSpend / income) * 100 : 0

        return MonthlySummary(
            income: income,
            fixedCosts: 0,
            envelopesTotal: totalBudgeted,
            totalBudgeted: totalBudgeted,
            actualSpend: actualSpend,
            surplus: income - totalBudgeted,
            projectedTotal: projectedTotal,
            pctOfIncomeBudgeted: pctOfIncomeBudgeted,
            pctSpent: pctSpent
        )
    }
}

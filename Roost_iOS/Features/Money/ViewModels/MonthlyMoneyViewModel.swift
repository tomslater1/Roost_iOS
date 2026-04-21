import Foundation
import Observation
import Realtime

@MainActor
@Observable
final class MonthlyMoneyViewModel {

    var summary: MonthlySummary?
    var selectedMonth: Date = Date().startOfMonth
    var isLoading = false
    var error: Error?

    @ObservationIgnored
    private let service = MonthlyMoneyService()

    @ObservationIgnored
    private let expenseRepository = ExpenseRepository()

    @ObservationIgnored
    private let budgetRepository = BudgetRepository()

    @ObservationIgnored
    private var incomeSubscriptionId: UUID?

    @ObservationIgnored
    private var memberIncomeSubscriptionId: UUID?

    @ObservationIgnored
    private var subscribedHomeId: UUID?

    // MARK: - Computed

    var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
    }

    var daysElapsed: Int {
        let cal = Calendar.current
        let today = Date()
        // For past months, all days are elapsed
        guard cal.isDate(today, equalTo: selectedMonth, toGranularity: .month) else {
            return daysInMonth
        }
        return cal.component(.day, from: today)
    }

    var dailySpendRate: Decimal? {
        guard let summary, daysElapsed > 0 else { return nil }
        return summary.actualSpend / Decimal(daysElapsed)
    }

    var projectedLifestyleSpend: Decimal? {
        guard let rate = dailySpendRate else { return nil }
        return rate * Decimal(daysInMonth)
    }

    var projectedSurplus: Decimal? {
        guard let summary, let projected = projectedLifestyleSpend else { return nil }
        return summary.income - summary.fixedCosts - projected
    }

    // MARK: - Load

    func loadSummary(homeId: UUID, members: [HomeMember] = []) async {
        isLoading = true
        error = nil
        do {
            summary = try await service.fetchMonthlySummary(homeId: homeId, month: selectedMonth)
        } catch {
            if !isCancellation(error) {
                // Offline fallback: server RPC is unreachable, so compute a
                // coarse `MonthlySummary` from cached expenses + budgets +
                // in-memory home members. Accuracy is lower (fixed vs
                // envelope split is rolled into `totalBudgeted`) but it
                // keeps the Money screen readable; the server reconciles
                // on next online refresh.
                if isNetworkFailure(error), !members.isEmpty {
                    let cachedExpenses = (try? expenseRepository.loadCached(homeID: homeId)) ?? []
                    let cachedBudgets = (try? budgetRepository.loadCached(homeID: homeId)) ?? []
                    summary = MonthlyMoneyCalculator.compute(
                        members: members,
                        expenses: cachedExpenses,
                        budgets: cachedBudgets,
                        month: selectedMonth
                    )
                } else {
                    self.error = error
                }
            }
        }
        isLoading = false
    }

    func navigateMonth(direction: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: direction, to: selectedMonth) else { return }
        // Clamp forward navigation at current month
        if direction > 0 && next > Date().startOfMonth { return }
        selectedMonth = next.startOfMonth
        summary = nil
    }

    // MARK: - Realtime

    func startRealtime(homeId: UUID) async {
        if let existing = subscribedHomeId, existing != homeId { await stopRealtime() }
        guard incomeSubscriptionId == nil, memberIncomeSubscriptionId == nil else { return }
        subscribedHomeId = homeId

        incomeSubscriptionId = await RealtimeManager.shared.subscribe(
            table: "household_income",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self, let hid = self.subscribedHomeId else { return }
            await self.loadSummary(homeId: hid)
        }

        memberIncomeSubscriptionId = await RealtimeManager.shared.subscribe(
            table: "home_members",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self, let hid = self.subscribedHomeId else { return }
            await self.loadSummary(homeId: hid)
        }
    }

    func stopRealtime() async {
        if let id = incomeSubscriptionId {
            await RealtimeManager.shared.unsubscribe(table: "household_income", callbackId: id)
            incomeSubscriptionId = nil
        }
        if let id = memberIncomeSubscriptionId {
            await RealtimeManager.shared.unsubscribe(table: "home_members", callbackId: id)
            memberIncomeSubscriptionId = nil
        }
        subscribedHomeId = nil
    }

    // MARK: - Private

    private func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled ||
        (error as NSError).code == NSURLErrorCancelled
    }

    /// Matches URLError codes that indicate the device is offline or cannot
    /// reach the server. Used to decide whether to attempt the local-compute
    /// fallback for the monthly summary.
    private func isNetworkFailure(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        return false
    }
}

// MARK: - Date helpers

private extension Date {
    var startOfMonth: Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: self)
        ) ?? self
    }
}

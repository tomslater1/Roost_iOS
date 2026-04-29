import Foundation
import Observation
import Realtime

@MainActor
@Observable
final class ExpensesViewModel {
    var expenses: [ExpenseWithSplits] = []
    var isLoading = false
    var errorMessage: String?
    var settleUpSuccess = false

    // Hazel feedback — set briefly after auto-categorization, cleared after 3s
    var lastHazelCategorization: String?
    var isBulkCategorizing = false

    @ObservationIgnored
    private let expenseService = ExpenseService()

    @ObservationIgnored
    private let hazelService = HazelService()

    @ObservationIgnored
    private var realtimeSubscriptionId: UUID?

    @ObservationIgnored
    private var subscribedHomeId: UUID?

    init(
        expenses: [ExpenseWithSplits] = [],
        isLoading: Bool = false,
        errorMessage: String? = nil,
        settleUpSuccess: Bool = false
    ) {
        self.expenses = expenses
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.settleUpSuccess = settleUpSuccess
    }

    /// Net balance: positive = I am owed, negative = I owe
    func balance(myUserId: UUID, partnerUserId: UUID) -> Decimal {
        BalanceCalculator.calculate(
            expenses: expenses,
            myUserId: myUserId,
            partnerUserId: partnerUserId
        )
    }

    func loadExpenses(homeId: UUID) async {
        isLoading = true
        errorMessage = nil

        do {
            expenses = try await expenseService.fetchExpenses(for: homeId)
        } catch {
            if !isCancellation(error) {
                errorMessage = String(describing: error)
            }
        }

        isLoading = false
    }

    func addExpense(
        title: String,
        amount: Decimal,
        paidByUserId: UUID,
        splitType: String,
        category: String?,
        notes: String?,
        incurredOn: Date,
        homeId: UUID,
        myUserId: UUID,
        partnerUserId: UUID,
        isRecurring: Bool = false,
        hazelEnabled: Bool = false,
        isNest: Bool = false,
        budgetCategoryNames: [String] = []
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, amount > 0 else { return }

        var resolvedTitle = trimmedTitle
        var resolvedCategory = category?.isEmpty == true ? nil : category

        // Hazel expense categorization is Pro-only
        if hazelEnabled, isNest, resolvedCategory == nil {
            let hazelCategories: [String] = budgetCategoryNames.isEmpty
                ? Array(Set(
                    expenses.compactMap(\.category)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )).sorted()
                : budgetCategoryNames
            if let result = await hazelService.categorizeExpense(
                text: trimmedTitle,
                categories: hazelCategories,
                homeId: homeId
            ) {
                resolvedTitle = result.text
                resolvedCategory = result.category
                lastHazelCategorization = result.category
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    self?.lastHazelCategorization = nil
                }
            }
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: incurredOn)

        let createExpense = CreateExpense(
            homeID: homeId,
            title: resolvedTitle,
            amount: amount,
            paidBy: paidByUserId,
            splitType: splitType,
            category: resolvedCategory,
            notes: notes?.isEmpty == true ? nil : notes,
            incurredOn: dateString,
            isRecurring: isRecurring ? true : nil
        )

        // Build splits based on split type
        var splits: [CreateExpenseSplit] = []
        if splitType == "equal" {
            let halfAmount = amount / 2
            // Payer's split — settled immediately
            splits.append(CreateExpenseSplit(
                userID: paidByUserId,
                amount: halfAmount,
                settledAt: Date()
            ))
            // Other person's split — unsettled
            let otherUserId = (paidByUserId == myUserId) ? partnerUserId : myUserId
            splits.append(CreateExpenseSplit(
                userID: otherUserId,
                amount: halfAmount,
                settledAt: nil
            ))
        }
        // Solo: no splits

        do {
            _ = try await expenseService.createExpense(createExpense, splits: splits)
            // Reload to get the full ExpenseWithSplits from server
            await loadExpenses(homeId: homeId)
            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: myUserId.uuidString,
                action: "added expense \(resolvedTitle)",
                entityType: "expense"
            )
        } catch {
            if !isCancellation(error) {
                errorMessage = String(describing: error)
            }
        }
    }

    func deleteExpense(_ expense: ExpenseWithSplits, homeId: UUID, userId: UUID) async {
        guard let index = expenses.firstIndex(where: { $0.id == expense.id }) else { return }

        // Optimistic
        let removed = expenses.remove(at: index)

        do {
            try await expenseService.deleteExpense(id: removed.id)
            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: userId.uuidString,
                action: "removed expense \(removed.title)",
                entityType: "expense",
                entityId: removed.id.uuidString
            )
        } catch {
            expenses.insert(removed, at: min(index, expenses.count))
            if !isCancellation(error) {
                errorMessage = String(describing: error)
            }
        }
    }

    func updateExpense(
        _ original: ExpenseWithSplits,
        title: String,
        amount: Decimal,
        paidByUserId: UUID,
        splitType: String,
        category: String?,
        notes: String?,
        incurredOn: Date,
        homeId: UUID,
        myUserId: UUID,
        partnerUserId: UUID,
        isRecurring: Bool = false
    ) async {
        guard let index = expenses.firstIndex(where: { $0.id == original.id }) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, amount > 0 else { return }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: incurredOn)

        let updatedExpense = Expense(
            id: original.id,
            homeID: original.homeID,
            title: trimmedTitle,
            amount: amount,
            paidBy: paidByUserId,
            splitType: splitType,
            category: category?.isEmpty == true ? nil : category,
            notes: notes?.isEmpty == true ? nil : notes,
            incurredOn: dateString,
            isRecurring: isRecurring ? true : nil,
            createdAt: original.createdAt
        )

        let updatedSplits: [ExpenseSplit]
        if shouldRebuildSplits(original: original, amount: amount, paidByUserId: paidByUserId, splitType: splitType) {
            updatedSplits = makeSplits(
                amount: amount,
                splitType: splitType,
                paidByUserId: paidByUserId,
                myUserId: myUserId,
                partnerUserId: partnerUserId,
                expenseId: original.id
            )
        } else {
            updatedSplits = original.expenseSplits
        }

        let optimisticExpense = ExpenseWithSplits(
            id: original.id,
            homeID: original.homeID,
            title: trimmedTitle,
            amount: amount,
            paidBy: paidByUserId,
            splitType: splitType,
            category: category?.isEmpty == true ? nil : category,
            notes: notes?.isEmpty == true ? nil : notes,
            incurredOn: dateString,
            isRecurring: isRecurring ? true : nil,
            createdAt: original.createdAt,
            expenseSplits: updatedSplits
        )

        expenses[index] = optimisticExpense

        do {
            let confirmedExpense = try await expenseService.replaceExpense(updatedExpense, splits: updatedSplits.toCreateSplits())
            expenses[index] = confirmedExpense
            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: myUserId.uuidString,
                action: "updated expense \(trimmedTitle)",
                entityType: "expense",
                entityId: original.id.uuidString
            )
        } catch {
            expenses[index] = original
            if !isCancellation(error) {
                errorMessage = String(describing: error)
            }
        }
    }

    func settleUp(
        homeId: UUID,
        fromUserId: UUID,
        toUserId: UUID,
        amount: Decimal,
        note: String?,
        myUserId: UUID
    ) async {
        do {
            try await expenseService.settleUp(
                homeID: homeId,
                paidBy: fromUserId,
                paidTo: toUserId,
                amount: amount,
                note: note?.isEmpty == true ? nil : note
            )
            settleUpSuccess = true
            // Reload to reflect settled splits
            await loadExpenses(homeId: homeId)
            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: myUserId.uuidString,
                action: "settled up",
                entityType: "settlement"
            )
        } catch {
            if !isCancellation(error) {
                errorMessage = String(describing: error)
            }
        }
    }

    // MARK: - Hazel Bulk Categorize (Pro)

    /// Categorizes up to 20 uncategorized expenses in the current month using Hazel.
    func bulkCategorizeUncategorized(
        homeId: UUID,
        myUserId: UUID,
        partnerUserId: UUID?,
        budgetCategoryNames: [String]
    ) async {
        guard !isBulkCategorizing else { return }

        let cal = Calendar.current
        let now = Date()
        let uncategorized = expenses.filter { exp in
            let category = exp.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard category.isEmpty else { return false }
            guard let date = exp.incurredOnDate else { return false }
            return cal.isDate(date, equalTo: now, toGranularity: .month)
        }.prefix(20)

        guard !uncategorized.isEmpty else { return }

        isBulkCategorizing = true
        defer { isBulkCategorizing = false }

        let categories = budgetCategoryNames.isEmpty
            ? Array(Set(expenses.compactMap(\.category).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
            : budgetCategoryNames

        for exp in uncategorized {
            guard let result = await hazelService.categorizeExpense(
                text: exp.title,
                categories: categories,
                homeId: homeId
            ) else { continue }

            await updateExpense(
                exp,
                title: result.text,
                amount: exp.amount,
                paidByUserId: exp.paidBy,
                splitType: exp.splitType ?? "equal",
                category: result.category,
                notes: exp.notes,
                incurredOn: exp.incurredOnDate ?? now,
                homeId: homeId,
                myUserId: myUserId,
                partnerUserId: partnerUserId ?? myUserId,
                isRecurring: exp.isRecurring ?? false
            )
        }
    }

    // MARK: - Realtime

    func startRealtime(homeId: UUID) async {
        if let subscribedHomeId, subscribedHomeId != homeId {
            await stopRealtime()
        }
        guard realtimeSubscriptionId == nil else { return }
        subscribedHomeId = homeId

        realtimeSubscriptionId = await RealtimeManager.shared.subscribe(
            table: "expenses",
            filter: .eq("home_id", value: homeId.uuidString)
        ) { [weak self] in
            guard let self, let homeId = self.subscribedHomeId else { return }
            await self.loadExpenses(homeId: homeId)
        }
    }

    func stopRealtime() async {
        guard let subId = realtimeSubscriptionId else { return }
        await RealtimeManager.shared.unsubscribe(table: "expenses", callbackId: subId)
        realtimeSubscriptionId = nil
        subscribedHomeId = nil
    }

    private func makeSplits(
        amount: Decimal,
        splitType: String,
        paidByUserId: UUID,
        myUserId: UUID,
        partnerUserId: UUID,
        expenseId: UUID
    ) -> [ExpenseSplit] {
        guard splitType == "equal" else { return [] }

        let halfAmount = amount / 2
        let otherUserId = paidByUserId == myUserId ? partnerUserId : myUserId

        return [
            ExpenseSplit(
                id: UUID(),
                expenseID: expenseId,
                userID: paidByUserId,
                amount: halfAmount,
                settledAt: Date(),
                settled: true
            ),
            ExpenseSplit(
                id: UUID(),
                expenseID: expenseId,
                userID: otherUserId,
                amount: halfAmount,
                settledAt: nil,
                settled: false
            )
        ]
    }

    private func isCancellation(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled ||
        (error as NSError).code == NSURLErrorCancelled
    }

    private func shouldRebuildSplits(
        original: ExpenseWithSplits,
        amount: Decimal,
        paidByUserId: UUID,
        splitType: String
    ) -> Bool {
        original.amount != amount
            || original.paidBy != paidByUserId
            || (original.splitType ?? "equal").lowercased() != splitType.lowercased()
    }
}

private extension Array where Element == ExpenseSplit {
    func toCreateSplits() -> [CreateExpenseSplit] {
        map { split in
            CreateExpenseSplit(
                userID: split.userID,
                amount: split.amount,
                settledAt: split.settledAt
            )
        }
    }
}

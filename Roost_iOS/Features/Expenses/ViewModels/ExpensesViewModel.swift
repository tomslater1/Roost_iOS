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
    var lastHazelCategorization: String?
    var isBulkCategorizing = false

    @ObservationIgnored
    private let expenseService = ExpenseService()

    @ObservationIgnored
    private let hazelService = HazelService()

    @ObservationIgnored
    private let repository = ExpenseRepository()

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

    /// Cache-first load: paint from SwiftData immediately so the screen
    /// renders without waiting for the network, then refresh in the
    /// background. On offline, the refresh silently fails and the cached
    /// snapshot is the user-visible state.
    func loadExpenses(homeId: UUID) async {
        isLoading = true
        errorMessage = nil

        // 1. Paint from cache.
        if let cached = try? repository.loadCached(homeID: homeId) {
            expenses = cached
        }

        // 2. Refresh from network if possible.
        do {
            try await repository.refresh(homeID: homeId)
            expenses = (try? repository.loadCached(homeID: homeId)) ?? expenses
        } catch {
            if !isCancellation(error) {
                // Cache is already painted; only surface the error when there
                // was no cached fallback to render.
                if expenses.isEmpty {
                    errorMessage = String(describing: error)
                }
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
        isPro: Bool = false,
        budgetCategoryNames: [String] = []
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, amount > 0 else { return }

        var resolvedTitle = trimmedTitle
        var resolvedCategory = category?.isEmpty == true ? nil : category

        // Hazel expense categorisation is Pro-only. When online we run it
        // synchronously; when offline, we skip it (an offline-created expense
        // lands uncategorised and the user can edit it later, or run bulk
        // categorisation after reconnect).
        if hazelEnabled, isPro, resolvedCategory == nil {
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
                if let cat = resolvedCategory {
                    lastHazelCategorization = cat
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(3))
                        self?.lastHazelCategorization = nil
                    }
                }
            }
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: incurredOn)

        // Client-supplied UUID — survives the offline → online round trip.
        let clientID = UUID()

        let insert = InsertExpense(
            id: clientID,
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

        // Build splits based on split type.
        let createSplits: [CreateExpenseSplit] = makeCreateSplits(
            amount: amount,
            splitType: splitType,
            paidByUserId: paidByUserId,
            myUserId: myUserId,
            partnerUserId: partnerUserId
        )

        let optimisticExpense = Expense(
            id: clientID,
            homeID: homeId,
            title: resolvedTitle,
            amount: amount,
            paidBy: paidByUserId,
            splitType: splitType,
            category: resolvedCategory,
            notes: notes?.isEmpty == true ? nil : notes,
            incurredOn: dateString,
            isRecurring: isRecurring ? true : nil,
            createdAt: Date()
        )
        let optimisticSplits: [ExpenseSplit] = createSplits.map { split in
            ExpenseSplit(
                id: UUID(),
                expenseID: clientID,
                userID: split.userID,
                amount: split.amount,
                settledAt: split.settledAt,
                settled: split.settledAt != nil
            )
        }

        do {
            try repository.applyOptimisticUpsert(
                expense: optimisticExpense,
                splits: optimisticSplits,
                pendingOperation: "create"
            )
            let payload = ExpenseCreatePayload(
                expense: insert,
                splits: createSplits.map(CreateExpenseSplitPayload.init)
            )
            let payloadData = try JSONEncoder.mutation.encode(payload)
            try OfflineAwareWrite.enqueue(OfflineAwareWrite.Intent(
                entityType: "expense",
                operation: "create",
                targetID: clientID,
                homeID: homeId,
                payload: payloadData
            ))

            // Optimistic UI refresh from cache.
            expenses = (try? repository.loadCached(homeID: homeId)) ?? expenses
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
        guard expenses.firstIndex(where: { $0.id == expense.id }) != nil else { return }

        do {
            try repository.applyOptimisticDelete(expenseID: expense.id)
            try OfflineAwareWrite.enqueue(OfflineAwareWrite.Intent(
                entityType: "expense",
                operation: "delete",
                targetID: expense.id,
                homeID: homeId,
                payload: Data() // targetID is all the delete replay needs
            ))
            expenses = (try? repository.loadCached(homeID: homeId)) ?? expenses.filter { $0.id != expense.id }
            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: userId.uuidString,
                action: "removed expense \(expense.title)",
                entityType: "expense",
                entityId: expense.id.uuidString
            )
        } catch {
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
        guard expenses.firstIndex(where: { $0.id == original.id }) != nil else { return }

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

        do {
            try repository.applyOptimisticUpsert(
                expense: updatedExpense,
                splits: updatedSplits,
                pendingOperation: "update"
            )
            let payload = ExpenseUpdatePayload(
                expense: updatedExpense,
                splits: updatedSplits.toCreateSplits().map(CreateExpenseSplitPayload.init)
            )
            let payloadData = try JSONEncoder.mutation.encode(payload)
            try OfflineAwareWrite.enqueue(OfflineAwareWrite.Intent(
                entityType: "expense",
                operation: "update",
                targetID: original.id,
                homeID: homeId,
                payload: payloadData
            ))
            expenses = (try? repository.loadCached(homeID: homeId)) ?? expenses
            ActivityService.logActivity(
                homeId: homeId.uuidString,
                userId: myUserId.uuidString,
                action: "updated expense \(trimmedTitle)",
                entityType: "expense",
                entityId: original.id.uuidString
            )
        } catch {
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
        // Collect expense IDs whose splits this settlement will affect —
        // those are the unsettled splits between the two users in the home.
        let affectedExpenseIDs: [UUID] = expenses.compactMap { ews in
            guard ews.homeID == homeId else { return nil }
            let hasUnsettledSplit = ews.expenseSplits.contains { split in
                (split.settledAt == nil)
                    && ((split.userID == fromUserId && ews.paidBy == toUserId)
                        || (split.userID == toUserId && ews.paidBy == fromUserId))
            }
            return hasUnsettledSplit ? ews.id : nil
        }

        do {
            try repository.applyOptimisticSettlement(affectedExpenseIDs: affectedExpenseIDs)
            let payload = ExpenseSettlementPayload(
                homeID: homeId,
                paidBy: fromUserId,
                paidTo: toUserId,
                amount: amount,
                note: note?.isEmpty == true ? nil : note,
                affectedExpenseIDs: affectedExpenseIDs
            )
            let payloadData = try JSONEncoder.mutation.encode(payload)
            try OfflineAwareWrite.enqueue(OfflineAwareWrite.Intent(
                entityType: "expense",
                operation: "settlement",
                targetID: homeId, // settlements don't target a single expense
                homeID: homeId,
                payload: payloadData
            ))
            settleUpSuccess = true
            expenses = (try? repository.loadCached(homeID: homeId)) ?? expenses
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

    // MARK: - Hazel Bulk Categorize

    func bulkCategorizeUncategorized(
        homeId: UUID,
        myUserId: UUID,
        partnerUserId: UUID?,
        budgetCategoryNames: [String]
    ) async {
        guard !isBulkCategorizing else { return }
        let cal = Calendar.current
        let now = Date()
        let uncategorized = expenses.filter { ews in
            let hasCategory = ews.category.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
            guard !hasCategory else { return false }
            guard let date = ews.incurredOnDate else { return false }
            return cal.isDate(date, equalTo: now, toGranularity: .month)
        }.prefix(20)
        guard !uncategorized.isEmpty else { return }

        isBulkCategorizing = true
        let categories = budgetCategoryNames.isEmpty
            ? Array(Set(expenses.compactMap(\.category).filter { !$0.isEmpty })).sorted()
            : budgetCategoryNames

        for ews in uncategorized {
            guard let result = await hazelService.categorizeExpense(
                text: ews.title,
                categories: categories,
                homeId: homeId
            ) else { continue }
            await updateExpense(
                ews,
                title: result.text,
                amount: ews.amount,
                paidByUserId: ews.paidBy,
                splitType: ews.splitType ?? "equal",
                category: result.category,
                notes: ews.notes,
                incurredOn: ews.incurredOnDate ?? now,
                homeId: homeId,
                myUserId: myUserId,
                partnerUserId: partnerUserId ?? myUserId
            )
        }
        isBulkCategorizing = false
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

    private func makeCreateSplits(
        amount: Decimal,
        splitType: String,
        paidByUserId: UUID,
        myUserId: UUID,
        partnerUserId: UUID
    ) -> [CreateExpenseSplit] {
        guard splitType == "equal" else { return [] }
        let halfAmount = amount / 2
        let otherUserId = paidByUserId == myUserId ? partnerUserId : myUserId
        return [
            CreateExpenseSplit(userID: paidByUserId, amount: halfAmount, settledAt: Date()),
            CreateExpenseSplit(userID: otherUserId, amount: halfAmount, settledAt: nil)
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

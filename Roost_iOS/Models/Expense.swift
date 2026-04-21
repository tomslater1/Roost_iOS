import Foundation

struct Expense: Codable, Identifiable, Hashable {
    let id: UUID
    var homeID: UUID
    var title: String
    var amount: Decimal
    var paidBy: UUID
    var splitType: String?
    var category: String?
    var notes: String?
    var incurredOn: String
    var isRecurring: Bool?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case title
        case amount
        case paidBy = "paid_by"
        case splitType = "split_type"
        case category
        case notes
        case incurredOn = "date"
        case isRecurring = "is_recurring"
        case createdAt = "created_at"
    }

    /// Parse the date-only string from Supabase
    var incurredOnDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let d = formatter.date(from: incurredOn) { return d }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: incurredOn)
    }
}

struct ExpenseSplit: Codable, Identifiable, Hashable {
    let id: UUID
    var expenseID: UUID
    var userID: UUID
    var amount: Decimal
    var settledAt: Date?
    var settled: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case expenseID = "expense_id"
        case userID = "user_id"
        case amount
        case settledAt = "settled_at"
        case settled
    }
}

/// Decoded directly from PostgREST `select("*, expense_splits(*)")` response.
struct ExpenseWithSplits: Codable, Identifiable, Hashable {
    let id: UUID
    var homeID: UUID
    var title: String
    var amount: Decimal
    var paidBy: UUID
    var splitType: String?
    var category: String?
    var notes: String?
    var incurredOn: String
    var isRecurring: Bool?
    var createdAt: Date
    var expenseSplits: [ExpenseSplit]

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case title
        case amount
        case paidBy = "paid_by"
        case splitType = "split_type"
        case category
        case notes
        case incurredOn = "date"
        case isRecurring = "is_recurring"
        case createdAt = "created_at"
        case expenseSplits = "expense_splits"
    }

    var expense: Expense {
        Expense(
            id: id,
            homeID: homeID,
            title: title,
            amount: amount,
            paidBy: paidBy,
            splitType: splitType,
            category: category,
            notes: notes,
            incurredOn: incurredOn,
            isRecurring: isRecurring,
            createdAt: createdAt
        )
    }

    /// Parse the date-only string from Supabase
    var incurredOnDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let d = formatter.date(from: incurredOn) { return d }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: incurredOn)
    }
}

struct CreateExpenseSplit: Hashable {
    var userID: UUID
    var amount: Decimal
    var settledAt: Date?
}

struct InsertExpenseSplit: Codable, Hashable {
    var expenseID: UUID
    var userID: UUID
    var amount: Decimal
    var settledAt: Date?

    enum CodingKeys: String, CodingKey {
        case expenseID = "expense_id"
        case userID = "user_id"
        case amount
        case settledAt = "settled_at"
    }
}

struct CreateExpense: Codable, Hashable {
    var homeID: UUID
    var title: String
    var amount: Decimal
    var paidBy: UUID
    var splitType: String
    var category: String?
    var notes: String?
    var incurredOn: String
    var isRecurring: Bool?

    enum CodingKeys: String, CodingKey {
        case homeID = "home_id"
        case title
        case amount
        case paidBy = "paid_by"
        case splitType = "split_type"
        case category
        case notes
        case incurredOn = "date"
        case isRecurring = "is_recurring"
    }
}

/// Same shape as `CreateExpense` but carries a **client-supplied UUID**. Used
/// by the offline mutation queue so the cached row and the eventual server
/// row share the same primary key, preserving referential integrity for any
/// follow-up offline edits of the same expense.
struct InsertExpense: Codable, Hashable {
    var id: UUID
    var homeID: UUID
    var title: String
    var amount: Decimal
    var paidBy: UUID
    var splitType: String
    var category: String?
    var notes: String?
    var incurredOn: String
    var isRecurring: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case title
        case amount
        case paidBy = "paid_by"
        case splitType = "split_type"
        case category
        case notes
        case incurredOn = "date"
        case isRecurring = "is_recurring"
    }
}

struct Settlement: Codable, Identifiable, Hashable {
    let id: UUID
    var homeID: UUID?
    var paidBy: UUID
    var paidTo: UUID
    var amount: Decimal
    var note: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case paidBy = "paid_by"
        case paidTo = "paid_to"
        case amount
        case note
        case createdAt = "created_at"
    }
}

import Foundation

struct SavingsGoal: Codable, Identifiable {
    let id: UUID
    let homeId: UUID
    var name: String
    var targetAmount: Decimal
    var savedAmount: Decimal
    var colour: String          // "terracotta" | "sage" | "amber" | "blue" | "purple" | "green"
    var icon: String?
    var targetDate: Date?
    var isComplete: Bool
    var completedAt: Date?
    var sortOrder: Int?
    var monthlyContribution: Decimal?
    var contributionDay: Int?   // day of month (1–28), default 1
    var budgetLineId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case targetAmount = "target_amount"
        case savedAmount = "current_amount"
        case colour
        case color
        case icon
        case targetDate = "target_date"
        case isComplete = "is_complete"
        case completedAt = "completed_at"
        case sortOrder = "sort_order"
        case monthlyContribution = "monthly_contribution"
        case contributionDay = "contribution_day"
        case budgetLineId = "budget_line_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        homeId: UUID,
        name: String,
        targetAmount: Decimal,
        savedAmount: Decimal,
        colour: String,
        icon: String?,
        targetDate: Date?,
        isComplete: Bool,
        completedAt: Date?,
        sortOrder: Int?,
        monthlyContribution: Decimal?,
        contributionDay: Int?,
        budgetLineId: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.homeId = homeId
        self.name = name
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.colour = colour
        self.icon = icon
        self.targetDate = targetDate
        self.isComplete = isComplete
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.monthlyContribution = monthlyContribution
        self.contributionDay = contributionDay
        self.budgetLineId = budgetLineId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeId = try container.decode(UUID.self, forKey: .homeId)
        name = try container.decode(String.self, forKey: .name)
        targetAmount = try container.decode(Decimal.self, forKey: .targetAmount)
        savedAmount = try container.decode(Decimal.self, forKey: .savedAmount)

        let decodedColour = (try? container.decodeIfPresent(String.self, forKey: .colour))
            ?? (try? container.decodeIfPresent(String.self, forKey: .color))
        let trimmedColour = decodedColour?.trimmingCharacters(in: .whitespacesAndNewlines)
        colour = trimmedColour?.isEmpty == false ? trimmedColour! : "terracotta"

        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        targetDate = container.decodeSavingsDateOnlyIfPresent(forKey: .targetDate)
        isComplete = (try container.decodeIfPresent(Bool.self, forKey: .isComplete)) ?? false
        completedAt = container.decodeSavingsTimestampIfPresent(forKey: .completedAt)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder)
        monthlyContribution = try container.decodeIfPresent(Decimal.self, forKey: .monthlyContribution)
        contributionDay = try container.decodeIfPresent(Int.self, forKey: .contributionDay)
        budgetLineId = try container.decodeIfPresent(UUID.self, forKey: .budgetLineId)
        createdAt = container.decodeSavingsTimestamp(forKey: .createdAt)
        updatedAt = container.decodeSavingsTimestamp(forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(homeId, forKey: .homeId)
        try container.encode(name, forKey: .name)
        try container.encode(targetAmount, forKey: .targetAmount)
        try container.encode(savedAmount, forKey: .savedAmount)
        try container.encode(colour, forKey: .colour)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeSavingsDateOnlyIfPresent(targetDate, forKey: .targetDate)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(monthlyContribution, forKey: .monthlyContribution)
        try container.encodeIfPresent(contributionDay, forKey: .contributionDay)
        try container.encodeIfPresent(budgetLineId, forKey: .budgetLineId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: savedAmount / targetAmount).doubleValue
        return min(1.0, max(0.0, ratio))
    }

    var isCompleted: Bool { isComplete || completedAt != nil }

    /// Months remaining until target date from today.
    var monthsRemaining: Int? {
        guard let target = targetDate else { return nil }
        let cal = Calendar.current
        let comps = cal.dateComponents([.month], from: Date(), to: target)
        return comps.month.map { max(0, $0) }
    }

    /// Monthly amount needed to reach target by target date.
    var monthlyNeeded: Decimal? {
        guard let months = monthsRemaining, months > 0 else { return nil }
        let remaining = targetAmount - savedAmount
        guard remaining > 0 else { return 0 }
        return remaining / Decimal(months)
    }
}

extension SavingsGoal: Equatable {
    static func == (lhs: SavingsGoal, rhs: SavingsGoal) -> Bool {
        lhs.id == rhs.id &&
        lhs.savedAmount == rhs.savedAmount &&
        lhs.targetAmount == rhs.targetAmount &&
        lhs.monthlyContribution == rhs.monthlyContribution &&
        lhs.isComplete == rhs.isComplete &&
        lhs.completedAt == rhs.completedAt &&
        lhs.name == rhs.name
    }
}

struct CreateSavingsGoal: Codable {
    var homeId: UUID
    var name: String
    var targetAmount: Decimal
    var savedAmount: Decimal
    var colour: String
    var icon: String?
    var targetDate: Date?
    var sortOrder: Int?
    var monthlyContribution: Decimal?
    var contributionDay: Int?

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case name
        case targetAmount = "target_amount"
        case savedAmount = "current_amount"
        case colour
        case icon
        case targetDate = "target_date"
        case sortOrder = "sort_order"
        case monthlyContribution = "monthly_contribution"
        case contributionDay = "contribution_day"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeId, forKey: .homeId)
        try container.encode(name, forKey: .name)
        try container.encode(targetAmount, forKey: .targetAmount)
        try container.encode(savedAmount, forKey: .savedAmount)
        try container.encode(colour, forKey: .colour)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeSavingsDateOnlyIfPresent(targetDate, forKey: .targetDate)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(monthlyContribution, forKey: .monthlyContribution)
        try container.encodeIfPresent(contributionDay, forKey: .contributionDay)
    }
}

/// Same shape as `CreateSavingsGoal` but carries a **client-supplied UUID**.
/// Used by the offline mutation queue so cached rows and eventual server
/// rows share the same primary key.
struct InsertSavingsGoal: Codable {
    var id: UUID
    var homeId: UUID
    var name: String
    var targetAmount: Decimal
    var savedAmount: Decimal
    var colour: String
    var icon: String?
    var targetDate: Date?
    var sortOrder: Int?
    var monthlyContribution: Decimal?
    var contributionDay: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case name
        case targetAmount = "target_amount"
        case savedAmount = "current_amount"
        case colour
        case icon
        case targetDate = "target_date"
        case sortOrder = "sort_order"
        case monthlyContribution = "monthly_contribution"
        case contributionDay = "contribution_day"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(homeId, forKey: .homeId)
        try container.encode(name, forKey: .name)
        try container.encode(targetAmount, forKey: .targetAmount)
        try container.encode(savedAmount, forKey: .savedAmount)
        try container.encode(colour, forKey: .colour)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeSavingsDateOnlyIfPresent(targetDate, forKey: .targetDate)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(monthlyContribution, forKey: .monthlyContribution)
        try container.encodeIfPresent(contributionDay, forKey: .contributionDay)
    }
}

private enum SavingsGoalDateCoding {
    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func timestamp(from rawValue: String) -> Date? {
        isoFractionalFormatter.date(from: rawValue)
            ?? isoFormatter.date(from: rawValue)
            ?? dateOnlyFormatter.date(from: rawValue)
    }
}

private extension KeyedDecodingContainer {
    func decodeSavingsDateOnlyIfPresent(forKey key: Key) -> Date? {
        guard let value = try? decodeIfPresent(String.self, forKey: key),
              !value.isEmpty else {
            return nil
        }

        return SavingsGoalDateCoding.dateOnlyFormatter.date(from: value)
            ?? SavingsGoalDateCoding.timestamp(from: value)
    }

    func decodeSavingsTimestampIfPresent(forKey key: Key) -> Date? {
        if let value = try? decodeIfPresent(String.self, forKey: key),
           !value.isEmpty {
            return SavingsGoalDateCoding.timestamp(from: value)
        }

        return try? decodeIfPresent(Date.self, forKey: key)
    }

    func decodeSavingsTimestamp(forKey key: Key) -> Date {
        decodeSavingsTimestampIfPresent(forKey: key) ?? Date()
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeSavingsDateOnlyIfPresent(_ date: Date?, forKey key: Key) throws {
        guard let date else {
            try encodeNil(forKey: key)
            return
        }

        try encode(SavingsGoalDateCoding.dateOnlyFormatter.string(from: date), forKey: key)
    }
}

import Foundation

struct Chore: Codable, Identifiable, Hashable {
    let id: UUID
    var homeID: UUID
    var title: String
    var description: String?
    var room: String?
    var assignedTo: UUID?
    var dueDate: Date?
    var completedBy: UUID?
    var frequency: String?
    var lastCompletedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case title
        case description
        case room
        case assignedTo = "assigned_to"
        case dueDate = "due_date"
        case completedBy = "completed_by"
        case frequency
        case lastCompletedAt = "last_completed_at"
        case createdAt = "created_at"
    }

    /// Convenience: chore is complete if someone has completed it
    var isCompleted: Bool { completedBy != nil }

    var isRecurring: Bool {
        guard let frequency else { return false }
        return frequency != "once"
    }

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: .now)
    }

    init(
        id: UUID,
        homeID: UUID,
        title: String,
        description: String? = nil,
        room: String? = nil,
        assignedTo: UUID? = nil,
        dueDate: Date? = nil,
        completedBy: UUID? = nil,
        frequency: String? = nil,
        lastCompletedAt: Date? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.homeID = homeID
        self.title = title
        self.description = description
        self.room = room
        self.assignedTo = assignedTo
        self.dueDate = dueDate
        self.completedBy = completedBy
        self.frequency = frequency
        self.lastCompletedAt = lastCompletedAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeID = try container.decode(UUID.self, forKey: .homeID)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        room = try container.decodeIfPresent(String.self, forKey: .room)
        assignedTo = try container.decodeIfPresent(UUID.self, forKey: .assignedTo)
        dueDate = try container.decodeDateOnlyIfPresent(forKey: .dueDate)
        completedBy = try container.decodeIfPresent(UUID.self, forKey: .completedBy)
        frequency = try container.decodeIfPresent(String.self, forKey: .frequency)
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(room, forKey: .room)
        try container.encodeIfPresent(assignedTo, forKey: .assignedTo)
        try container.encodeDateOnlyIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(completedBy, forKey: .completedBy)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encodeIfPresent(lastCompletedAt, forKey: .lastCompletedAt)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct CreateChore: Codable, Hashable {
    var homeID: UUID
    var title: String
    var description: String?
    var room: String?
    var assignedTo: UUID?
    var dueDate: Date?
    var frequency: String?

    enum CodingKeys: String, CodingKey {
        case homeID = "home_id"
        case title
        case description
        case room
        case assignedTo = "assigned_to"
        case dueDate = "due_date"
        case frequency
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(room, forKey: .room)
        try container.encodeIfPresent(assignedTo, forKey: .assignedTo)
        try container.encodeDateOnlyIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(frequency, forKey: .frequency)
    }
}

/// Like `CreateChore` but carries a client-supplied UUID + createdAt so
/// offline creates can be queued and later replayed against the server
/// without the server inventing a new ID (which would desync the
/// optimistic cache row).
struct InsertChore: Codable, Hashable {
    var id: UUID
    var homeID: UUID
    var title: String
    var description: String?
    var room: String?
    var assignedTo: UUID?
    var dueDate: Date?
    var frequency: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case homeID = "home_id"
        case title
        case description
        case room
        case assignedTo = "assigned_to"
        case dueDate = "due_date"
        case frequency
        case createdAt = "created_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(homeID, forKey: .homeID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(room, forKey: .room)
        try container.encodeIfPresent(assignedTo, forKey: .assignedTo)
        try container.encodeDateOnlyIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

private enum ChoreDateCoding {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

private extension KeyedDecodingContainer {
    func decodeDateOnlyIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        if let date = ChoreDateCoding.formatter.date(from: value) {
            return date
        }

        let context = DecodingError.Context(
            codingPath: codingPath + [key],
            debugDescription: "Invalid date-only format: \(value). Expected yyyy-MM-dd."
        )
        throw DecodingError.dataCorrupted(context)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeDateOnlyIfPresent(_ value: Date?, forKey key: Key) throws {
        guard let value else { return }
        try encode(ChoreDateCoding.formatter.string(from: value), forKey: key)
    }
}

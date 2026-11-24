import Foundation

/// Telephony.Sms.MESSAGE_TYPE_* values.
enum MessageType {
    static let inbox = 1
    static let sent = 2
    static let draft = 3
    static let outbox = 4
    static let failed = 5
    static let queued = 6
}

/// Telephony.Sms.STATUS_* values.
enum MessageStatus {
    static let none = -1
    static let complete = 0
    static let pending = 32
    static let failed = 64
}

/// SimpleContact as used for conversation participants: one address each.
struct Participant: Codable, Hashable {
    var name: String
    var number: String
}

/// Attachment: a file kept in the app's Attachments folder.
struct Attachment: Codable, Hashable, Identifiable {
    /// File name inside MessagesStore.attachmentsFolder.
    var id: String
    var mimetype: String
    /// Original (display) file name.
    var filename: String

    var url: URL { MessagesStore.attachmentsFolder.appendingPathComponent(id) }
}

/// Message (the Room entity, minus the provider-only bits).
struct Message: Codable, Hashable, Identifiable {
    var id: Int64
    var body: String
    var type: Int
    var status: Int
    var participants: [Participant]
    /// Seconds since 1970, like Fossify's Message.date.
    var date: Int
    var read: Bool
    var threadId: Int64
    var isMMS: Bool
    var attachments: [Attachment]
    var senderPhoneNumber: String
    var senderName: String
    var subscriptionId: Int
    var isScheduled: Bool
    /// Original millisecond timestamps from imported backups, kept for re-exporting.
    var dateMillis: Int64?
    var dateSentMillis: Int64?
    var subject: String?

    var isReceived: Bool { type == MessageType.inbox }
    var millis: Int64 { dateMillis ?? Int64(date) * 1000 }

    /// Message.getSender().
    var sender: Participant? {
        participants.first { $0.number.comparableNumber == senderPhoneNumber.comparableNumber }
            ?? participants.first { $0.name == senderName } ?? participants.first
    }
}

/// Per-thread data the system SMS database would keep (plus Fossify's own columns).
struct ThreadInfo: Codable, Hashable {
    var id: Int64
    var addresses: [String]
    var customTitle: String?
    var archived: Bool = false
}

/// Draft.
struct Draft: Codable, Hashable {
    var body: String
    var date: Int64
}

/// Conversation (computed from the thread and its messages).
struct Conversation: Identifiable, Hashable {
    var threadId: Int64
    var snippet: String
    var date: Int
    var read: Bool
    var title: String
    var isGroupConversation: Bool
    var phoneNumber: String
    var isScheduled: Bool
    var usesCustomTitle: Bool
    var isArchived: Bool
    var unreadCount: Int
    var participants: [Participant]

    var id: Int64 { threadId }
}

/// SearchResult.
struct SearchResult: Identifiable, Hashable {
    var messageId: Int64
    var title: String
    var snippet: String
    var date: String
    var threadId: Int64
    var number: String

    var id: String { "\(threadId)-\(messageId)" }
}

/// Items of the thread list (ThreadItems.kt).
enum ThreadItem: Identifiable, Hashable {
    case dateTime(Int)
    case message(Message)
    case error(Message)
    case sent(Int64, delivered: Bool)
    case sending(Int64)

    var id: String {
        switch self {
        case .dateTime(let d): return "d\(d)"
        case .message(let m): return "m\(m.id)"
        case .error(let m): return "e\(m.id)"
        case .sent(let id, _): return "s\(id)"
        case .sending(let id): return "o\(id)"
        }
    }
}

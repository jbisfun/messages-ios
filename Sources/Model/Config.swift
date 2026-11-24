import FossifyCommons
import Observation
import SwiftUI

/// Port of the messages Config (SharedPreferences -> UserDefaults); colors, font size and
/// date format live in FossifyCommons.
@Observable
final class Config {
    static let shared = Config()

    @ObservationIgnored private let d = UserDefaults.standard

    // Outgoing messages
    var showCharacterCounter: Bool { didSet { d.set(showCharacterCounter, forKey: "show_character_counter") } }
    var useSimpleCharacters: Bool { didSet { d.set(useSimpleCharacters, forKey: "use_simple_characters") } }
    var sendOnEnter: Bool { didSet { d.set(sendOnEnter, forKey: "send_on_enter") } }
    var sendLongMessageMMS: Bool { didSet { d.set(sendLongMessageMMS, forKey: "send_long_message_mms") } }
    var sendGroupMessageMMS: Bool { didSet { d.set(sendGroupMessageMMS, forKey: "send_group_message_mms") } }
    var mmsFileSizeLimit: Int64 { didSet { d.set(mmsFileSizeLimit, forKey: "mms_file_size_limit") } }

    /// prefs.contains(SEND_GROUP_MESSAGE_MMS).
    var isGroupMessageMmsPreferenceResolved: Bool { d.object(forKey: "send_group_message_mms") != nil }

    // Notifications
    var lockScreenVisibilitySetting: Int { didSet { d.set(lockScreenVisibilitySetting, forKey: "lock_screen_visibility") } }

    // Conversations
    var pinnedConversations: Set<String> { didSet { d.set(Array(pinnedConversations), forKey: "pinned_conversations") } }
    var blockedKeywords: Set<String> { didSet { d.set(Array(blockedKeywords), forKey: "blocked_keywords") } }
    var keepConversationsArchived: Bool { didSet { d.set(keepConversationsArchived, forKey: "keep_conversations_archived") } }
    var isArchiveAvailable: Bool { didSet { d.set(isArchiveAvailable, forKey: "is_archive_available") } }

    // Recycle bin
    var useRecycleBin: Bool { didSet { d.set(useRecycleBin, forKey: "use_recycle_bin") } }
    var lastRecycleBinCheck: Double { didSet { d.set(lastRecycleBinCheck, forKey: "last_recycle_bin_check") } }

    // Migrating
    var exportSms: Bool { didSet { d.set(exportSms, forKey: "export_sms") } }
    var exportMms: Bool { didSet { d.set(exportMms, forKey: "export_mms") } }
    var importSms: Bool { didSet { d.set(importSms, forKey: "import_sms") } }
    var importMms: Bool { didSet { d.set(importMms, forKey: "import_mms") } }

    private init() {
        showCharacterCounter = d.object(forKey: "show_character_counter") as? Bool ?? false
        useSimpleCharacters = d.object(forKey: "use_simple_characters") as? Bool ?? false
        sendOnEnter = d.object(forKey: "send_on_enter") as? Bool ?? false
        sendLongMessageMMS = d.object(forKey: "send_long_message_mms") as? Bool ?? false
        sendGroupMessageMMS = d.object(forKey: "send_group_message_mms") as? Bool ?? false
        mmsFileSizeLimit = (d.object(forKey: "mms_file_size_limit") as? NSNumber)?.int64Value ?? FileSize.kb200
        lockScreenVisibilitySetting = d.object(forKey: "lock_screen_visibility") as? Int ?? LockScreen.senderMessage
        pinnedConversations = Set(d.stringArray(forKey: "pinned_conversations") ?? [])
        blockedKeywords = Set(d.stringArray(forKey: "blocked_keywords") ?? [])
        keepConversationsArchived = d.object(forKey: "keep_conversations_archived") as? Bool ?? false
        isArchiveAvailable = d.object(forKey: "is_archive_available") as? Bool ?? true
        useRecycleBin = d.object(forKey: "use_recycle_bin") as? Bool ?? false
        lastRecycleBinCheck = d.double(forKey: "last_recycle_bin_check")
        exportSms = d.object(forKey: "export_sms") as? Bool ?? true
        exportMms = d.object(forKey: "export_mms") as? Bool ?? true
        importSms = d.object(forKey: "import_sms") as? Bool ?? true
        importMms = d.object(forKey: "import_mms") as? Bool ?? true
    }

    func isPinned(_ threadId: Int64) -> Bool { pinnedConversations.contains(String(threadId)) }
}

/// LOCK_SCREEN_* constants.
enum LockScreen {
    static let senderMessage = 1
    static let sender = 2
    static let nothing = 3

    static func title(_ v: Int) -> String {
        switch v {
        case senderMessage: return "Sender and message"
        case sender: return "Sender only"
        default: return "Nothing"
        }
    }
}

/// FILE_SIZE_* constants.
enum FileSize {
    static let none: Int64 = -1
    static let kb100: Int64 = 102_400
    static let kb200: Int64 = 204_800
    static let kb300: Int64 = 307_200
    static let kb600: Int64 = 614_400
    static let mb1: Int64 = 1_048_576
    static let mb2: Int64 = 2_097_152

    static let all: [(Int64, String)] = [
        (none, "No limit"), (mb2, "2MB"), (mb1, "1MB"), (kb600, "600KB"),
        (kb300, "300KB"), (kb200, "200KB"), (kb100, "100KB"),
    ]

    static func title(_ v: Int64) -> String { all.first { $0.0 == v }?.1 ?? "No limit" }
}

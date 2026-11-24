import FossifyCommons
import Foundation
import Observation

/// What the Android app reads from the telephony provider and its Room cache, kept by
/// the app itself: iOS gives third-party apps no access to the SMS database, so the
/// store holds imported backups and the messages sent from this app.
@MainActor
@Observable
final class MessagesStore {
    nonisolated static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Messages", isDirectory: true)
    }

    nonisolated static var attachmentsFolder: URL { folder.appendingPathComponent("Attachments", isDirectory: true) }
    nonisolated private static var file: URL { folder.appendingPathComponent("messages.json") }

    private(set) var threads: [Int64: ThreadInfo] = [:]
    private(set) var messages: [Message] = [] { didSet { reindex() } }
    private(set) var byThread: [Int64: [Message]] = [:]
    private(set) var drafts: [Int64: Draft] = [:]
    /// RecycleBinMessage: message id -> deletion time (ms).
    private(set) var recycleBin: [Int64: Int64] = [:]
    @ObservationIgnored private var nextId: Int64 = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var toast: String?
    /// Messages to hand to the system composer, one at a time.
    var composeQueue: [ComposeRequest] = []

    private struct FileData: Codable {
        var threads: [ThreadInfo]
        var messages: [Message]
        var drafts: [String: Draft]
        var recycleBin: [String: Int64]
        var nextId: Int64
    }

    init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let f = try? JSONDecoder().decode(FileData.self, from: data) else { return }
        threads = Dictionary(f.threads.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        messages = f.messages
        drafts = Dictionary(f.drafts.compactMap { k, v in Int64(k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        recycleBin = Dictionary(f.recycleBin.compactMap { k, v in Int64(k).map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        nextId = max(f.nextId, messages.map(\.id).max() ?? 0, threads.keys.max() ?? 0)
    }

    func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.writeNow()
        }
    }

    func writeNow() {
        let f = FileData(
            threads: Array(threads.values), messages: messages,
            drafts: Dictionary(uniqueKeysWithValues: drafts.map { (String($0.key), $0.value) }),
            recycleBin: Dictionary(uniqueKeysWithValues: recycleBin.map { (String($0.key), $0.value) }),
            nextId: nextId)
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(f).write(to: Self.file, options: .atomic)
        } catch {
            toast = "Couldn't save the message"
        }
    }

    private func reindex() {
        var map: [Int64: [Message]] = [:]
        for m in messages { map[m.threadId, default: []].append(m) }
        for k in map.keys { map[k]!.sort { ($0.date, $0.id) < ($1.date, $1.id) } }
        byThread = map
    }

    func newId() -> Int64 {
        nextId += 1
        return nextId
    }

    // MARK: Threads

    /// getThreadId(): the thread of exactly these recipients, created on demand.
    func threadId(for addresses: [String]) -> Int64 {
        var seen = Set<String>()
        let unique = addresses.filter { !$0.isEmpty && seen.insert($0.comparableNumber).inserted }
        let key = Set(unique.map(\.comparableNumber))
        if let t = threads.values.first(where: { Set($0.addresses.map(\.comparableNumber)) == key }) { return t.id }
        let id = newId()
        threads[id] = ThreadInfo(id: id, addresses: unique)
        save()
        return id
    }

    func participants(_ threadId: Int64, contacts: ContactsLookup) -> [Participant] {
        (threads[threadId]?.addresses ?? []).map { Participant(name: contacts.name(for: $0), number: $0) }
    }

    private func isBlocked(_ t: ThreadInfo) -> Bool {
        t.addresses.contains { BlockedNumbers.shared.isBlocked($0) }
    }

    func messages(_ threadId: Int64, recycleBin bin: Bool = false) -> [Message] {
        (byThread[threadId] ?? []).filter { (recycleBin[$0.id] != nil) == bin }
    }

    func message(_ id: Int64) -> Message? { messages.first { $0.id == id } }

    private func conversation(_ t: ThreadInfo, msgs: [Message], contacts: ContactsLookup) -> Conversation? {
        guard let last = msgs.last else { return nil }
        let people = t.addresses.map { Participant(name: contacts.name(for: $0), number: $0) }
        let unread = msgs.filter { !$0.read }.count
        return Conversation(
            threadId: t.id,
            snippet: last.body.isEmpty && !last.attachments.isEmpty ? "Attachment" : last.body,
            date: last.date,
            read: unread == 0,
            title: t.customTitle ?? people.map(\.name).joined(separator: ", "),
            isGroupConversation: t.addresses.count > 1,
            phoneNumber: t.addresses.first ?? "",
            isScheduled: msgs.allSatisfy(\.isScheduled),
            usesCustomTitle: t.customTitle != nil,
            isArchived: t.archived,
            unreadCount: unread,
            participants: people)
    }

    func conversation(_ threadId: Int64, contacts: ContactsLookup) -> Conversation? {
        guard let t = threads[threadId] else { return nil }
        return conversation(t, msgs: messages(threadId), contacts: contacts)
            ?? Conversation(threadId: t.id, snippet: "", date: 0, read: true,
                            title: t.customTitle ?? participants(threadId, contacts: contacts).map(\.name).joined(separator: ", "),
                            isGroupConversation: t.addresses.count > 1, phoneNumber: t.addresses.first ?? "",
                            isScheduled: false, usesCustomTitle: t.customTitle != nil, isArchived: t.archived,
                            unreadCount: 0, participants: participants(threadId, contacts: contacts))
    }

    /// getConversations() / getAllArchived(), without blocked numbers.
    func conversations(archived: Bool, contacts: ContactsLookup) -> [Conversation] {
        threads.values.filter { $0.archived == archived && !isBlocked($0) }
            .compactMap { conversation($0, msgs: messages($0.id), contacts: contacts) }
    }

    /// Conversations with messages in the recycle bin.
    func recycleBinConversations(contacts: ContactsLookup) -> [Conversation] {
        threads.values.compactMap { conversation($0, msgs: messages($0.id, recycleBin: true), contacts: contacts) }
            .sorted { $0.date > $1.date }
    }

    var recycleBinCount: Int { recycleBin.count }

    // MARK: Messages

    /// insertOrUpdateMessage(); unarchives the thread unless "Keep conversations archived".
    func upsert(_ m: Message) {
        if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i] = m } else { messages.append(m) }
        if threads[m.threadId]?.archived == true && !Config.shared.keepConversationsArchived && !m.isReceived {
            threads[m.threadId]?.archived = false
        }
        save()
    }

    func deleteMessages(_ ids: Set<Int64>, toRecycleBin: Bool) {
        if toRecycleBin {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            for id in ids { recycleBin[id] = now }
        } else {
            removeMessages { ids.contains($0.id) }
        }
        save()
    }

    func restoreMessages(_ ids: Set<Int64>) {
        for id in ids { recycleBin[id] = nil }
        save()
    }

    private func removeMessages(where pred: (Message) -> Bool) {
        let removed = messages.filter(pred)
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        messages.removeAll { ids.contains($0.id) }
        for id in ids { recycleBin[id] = nil }
        let stillUsed = Set(messages.flatMap { $0.attachments.map(\.id) })
        for a in removed.flatMap(\.attachments) where !stillUsed.contains(a.id) {
            try? FileManager.default.removeItem(at: a.url)
        }
        for m in removed where m.isScheduled { Scheduler.cancel(m.id) }
    }

    /// deleteConversation().
    func deleteConversations(_ threadIds: Set<Int64>) {
        removeMessages { threadIds.contains($0.threadId) }
        for id in threadIds {
            threads[id] = nil
            drafts[id] = nil
        }
        Config.shared.pinnedConversations.subtract(threadIds.map(String.init))
        save()
    }

    func setArchived(_ threadIds: Set<Int64>, _ archived: Bool) {
        for id in threadIds { threads[id]?.archived = archived }
        save()
    }

    func emptyArchive() {
        deleteConversations(Set(threads.values.filter(\.archived).map(\.id)))
    }

    func markRead(_ threadIds: Set<Int64>) { setRead(threadIds, true) }
    func markUnread(_ threadIds: Set<Int64>) { setRead(threadIds, false) }

    private func setRead(_ threadIds: Set<Int64>, _ read: Bool) {
        var changed = false
        for i in messages.indices where threadIds.contains(messages[i].threadId) && messages[i].read != read {
            messages[i].read = read
            changed = true
        }
        if changed { save() }
    }

    func rename(_ threadId: Int64, to title: String) {
        threads[threadId]?.customTitle = title
        save()
    }

    // MARK: Recycle bin

    func emptyRecycleBin() {
        let ids = Set(recycleBin.keys)
        removeMessages { ids.contains($0.id) }
        save()
    }

    func emptyRecycleBin(thread: Int64) {
        let ids = Set(messages(thread, recycleBin: true).map(\.id))
        removeMessages { ids.contains($0.id) }
        save()
    }

    func restoreAll(thread: Int64) {
        restoreMessages(Set(messages(thread, recycleBin: true).map(\.id)))
    }

    /// checkAndDeleteOldRecycleBinMessages(): items older than 30 days, checked daily.
    func checkAndDeleteOldRecycleBinMessages() {
        let config = Config.shared
        let now = Date().timeIntervalSince1970 * 1000
        guard config.useRecycleBin, config.lastRecycleBinCheck < now - 86_400_000 else { return }
        config.lastRecycleBinCheck = now
        let cutoff = Int64(now) - 30 * 86_400_000
        let old = Set(recycleBin.filter { $0.value < cutoff }.keys)
        guard !old.isEmpty else { return }
        removeMessages { old.contains($0.id) }
        save()
    }

    // MARK: Drafts

    func draft(_ threadId: Int64) -> String? { drafts[threadId]?.body }

    func saveDraft(_ threadId: Int64, _ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard drafts[threadId] != nil else { return }
            drafts[threadId] = nil
        } else {
            guard drafts[threadId]?.body != body else { return }
            drafts[threadId] = Draft(body: body, date: Int64(Date().timeIntervalSince1970 * 1000))
        }
        save()
    }

    // MARK: Search

    /// MainActivity.searchTextChanged(): conversation titles, then message bodies.
    func search(_ text: String, contacts: ContactsLookup) -> [SearchResult] {
        var results: [SearchResult] = []
        let blockedThreads = Set(threads.values.filter(isBlocked).map(\.id))
        for c in conversations(archived: false, contacts: contacts) + conversations(archived: true, contacts: contacts)
            where c.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            results.append(SearchResult(messageId: -1, title: c.title, snippet: c.phoneNumber,
                                        date: formatDateOrTime(c.date, hideTimeOnOtherDays: true, showCurrentYear: true),
                                        threadId: c.threadId, number: c.phoneNumber))
        }
        let matching = messages.filter {
            recycleBin[$0.id] == nil && !blockedThreads.contains($0.threadId)
                && $0.body.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        for m in matching.sorted(by: { $0.id > $1.id }) {
            var title = m.isReceived ? contacts.name(for: m.senderPhoneNumber) : ""
            if title.isEmpty { title = m.participants.map { contacts.name(for: $0.number) }.joined(separator: ", ") }
            results.append(SearchResult(messageId: m.id, title: title, snippet: m.body,
                                        date: formatDateOrTime(m.date, hideTimeOnOtherDays: true, showCurrentYear: true),
                                        threadId: m.threadId, number: m.isReceived ? m.senderPhoneNumber : (m.participants.first?.number ?? "")))
        }
        return results
    }

    /// getSuggestedContacts(): recent correspondents that are saved contacts.
    func suggestedContacts(contacts: ContactsLookup) -> [SimpleContact] {
        var seen = Set<String>()
        var out: [SimpleContact] = []
        for m in messages.sorted(by: { $0.date > $1.date }).prefix(50) {
            for p in m.participants {
                guard !BlockedNumbers.shared.isBlocked(p.number), let c = contacts.contact(for: p.number),
                      seen.insert(c.id).inserted else { continue }
                out.append(SimpleContact(id: c.id, name: c.name, numbers: [p.number], thumbnail: c.thumbnail))
            }
        }
        return Array(out.prefix(10))
    }

    // MARK: Sending

    /// Hands a message to the system composer (sendMessageCompat()).
    func send(_ request: ComposeRequest) {
        if request.separately && request.recipients.count > 1 {
            for r in request.recipients {
                var single = request
                single.recipients = [r]
                single.threadId = threadId(for: [r])
                single.separately = false
                composeQueue.append(single)
            }
        } else {
            composeQueue.append(request)
        }
    }

    /// Records what the composer did with the message.
    func composeFinished(_ r: ComposeRequest, sent: Bool, failed: Bool) {
        if !composeQueue.isEmpty { composeQueue.removeFirst() }
        if let old = r.replacing, !sent && !failed, let i = messages.firstIndex(where: { $0.id == old }),
           messages[i].isScheduled, messages[i].date <= Int(Date().timeIntervalSince1970) {
            // A due scheduled message the user didn't send: show it as not sent.
            messages[i].isScheduled = false
            messages[i].type = MessageType.failed
            messages[i].status = MessageStatus.failed
            save()
        }
        if let old = r.replacing, sent || failed {
            if let m = message(old), m.isScheduled { Scheduler.cancel(m.id) }
            messages.removeAll { $0.id == old }
        }
        guard sent || failed else { return }
        let people = r.recipients.map { Participant(name: r.names[$0] ?? $0, number: $0) }
        let id = newId()
        let m = Message(
            id: id, body: r.body, type: sent ? MessageType.sent : MessageType.failed,
            status: sent ? MessageStatus.none : MessageStatus.failed, participants: people,
            date: Int(Date().timeIntervalSince1970), read: true, threadId: r.threadId, isMMS: r.isMMS,
            attachments: r.attachments, senderPhoneNumber: "", senderName: "", subscriptionId: -1, isScheduled: false)
        upsert(m)
        drafts[r.threadId] = nil
    }

    // MARK: Scheduled messages

    func schedule(_ m: Message, title: String) {
        upsert(m)
        Scheduler.schedule(m, title: title)
    }

    func cancelScheduled(_ id: Int64) {
        removeMessages { $0.id == id }
        save()
    }

    /// Scheduled messages whose time has come (ScheduledMessageReceiver).
    var dueScheduled: [Message] {
        let now = Int(Date().timeIntervalSince1970)
        return messages.filter { $0.isScheduled && $0.date <= now }
    }

    // MARK: Import

    /// Adds imported messages, skipping ones already present (smsExist()/mmsExist()).
    func importMessages(_ list: [(addresses: [String], message: Message)]) -> (imported: Int, skipped: Int) {
        var existing = Set(messages.map { "\($0.millis)|\($0.type)|\($0.threadId)" })
        var imported = 0, skipped = 0
        for (addresses, var m) in list {
            let tid = threadId(for: addresses)
            m.threadId = tid
            let key = "\(m.millis)|\(m.type)|\(tid)"
            guard existing.insert(key).inserted else { skipped += 1; continue }
            m.id = newId()
            messages.append(m)
            imported += 1
        }
        save()
        return (imported, skipped)
    }
}

/// One message for MFMessageComposeViewController.
struct ComposeRequest: Identifiable {
    let id = UUID()
    var recipients: [String]
    var names: [String: String] = [:]
    var body: String
    var attachments: [Attachment] = []
    var threadId: Int64
    var isMMS: Bool
    var separately = false
    /// Scheduled or failed message this one replaces once sent.
    var replacing: Int64?
    /// Called with true when sent, false when cancelled.
    var onFinish: ((Bool) -> Void)?
}

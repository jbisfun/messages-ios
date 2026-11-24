import Contacts
import FossifyCommons
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import _PhotosUI_SwiftUI
import UIKit

/// ThreadActivity.
struct ThreadView: View {
    @Environment(MessagesStore.self) var store
    @Environment(ContactsLookup.self) var contacts
    @Environment(Router.self) var router
    @Environment(Config.self) var config
    @Environment(\.palette) var palette

    let route: ThreadRoute
    var threadId: Int64 { route.threadId }
    var isRecycleBin: Bool { route.isRecycleBin }

    @State var text = ""
    @State var attachments: [Attachment] = []
    @State var selection = Set<Int64>()
    @State var showPicker = false
    @FocusState var fieldFocused: Bool

    // Scheduling
    @State var isScheduled = false
    @State var scheduledDate = Date()
    @State var scheduledMessage: Message?
    @State var scheduleDialog = false
    @State var scheduledInfo: Message?

    @State var messageToResend: Int64?
    @State var groupSendDialog = false

    // Manage people (threadAddContacts)
    @State var managePeople = false
    @State var people: [Participant] = []
    @State var addQuery = ""

    // Dialogs and pickers
    @State var confirm: Confirmation?
    @State var deleteDialog = false
    @State var rename: Conversation?
    @State var details: Message?
    @State var selectText: String?
    @State var shortCodeInfo = false
    @State var quickLook: URL?
    @State var share: ShareItems?
    @State var shareText: String?
    @State var exportDocs: [AttachmentDocument] = []
    @State var exporting = false
    @State var photoItems: [PhotosPickerItem] = []
    @State var photoPicker = false
    @State var videoPicker = false
    @State var camera: Bool?
    @State var recorder = false
    @State var filePicker = false
    @State var contactPicker = false
    @State var atBottom = true
    @State var didSetup = false

    var body: some View {
        let msgs = store.messages(threadId, recycleBin: isRecycleBin)
        let participants = store.participants(threadId, contacts: contacts)
        let conversation = store.conversation(threadId, contacts: contacts)
        let special = participants.contains { $0.number.isShortCodeWithLetters }
        VStack(spacing: 0) {
            if selection.isEmpty {
                topBar(conversation: conversation, participants: participants, hasMessages: !msgs.isEmpty, special: special)
            } else {
                messagesActionBar(msgs)
            }
            if managePeople { managePeoplePanel }
            messageList(msgs)
            if !isRecycleBin {
                if special {
                    shortCodeHolder
                } else {
                    composeArea(participants: participants)
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear { setup(msgs) }
        .onDisappear {
            if !isRecycleBin && scheduledMessage == nil { store.saveDraft(threadId, text) }
            AudioPlayback.shared.stop()
        }
        .onChange(of: msgs.count) { _, _ in if !isRecycleBin { store.markRead([threadId]) } }
        .confirmation($confirm)
        .modifier(ThreadSheets(view: self))
    }

    private func setup(_ msgs: [Message]) {
        guard !didSetup else { return }
        didSetup = true
        if !isRecycleBin { store.markRead([threadId]) }
        if let t = route.text, !t.isEmpty { text = t } else if let d = store.draft(threadId) { text = d }
        if !route.attachments.isEmpty { attachments = route.attachments }
    }

    // MARK: Top bar (menu_thread)

    private func topBar(conversation: Conversation?, participants: [Participant], hasMessages: Bool, special: Bool) -> some View {
        let single = participants.count == 1 ? participants.first : nil
        let title = conversation?.title ?? participants.map(\.name).joined(separator: ", ")
        return TopBar(title: title) {
            if let p = single, !p.number.isShortCodeWithLetters, !isRecycleBin {
                IconButton(icon: "phone") { Launcher.call(p.number) }
            }
            if let c = conversation, hasMessages, !isRecycleBin, config.isArchiveAvailable {
                IconButton(icon: c.isArchived ? "tray.and.arrow.up" : "archivebox") {
                    store.setArchived([threadId], !c.isArchived)
                    router.pop()
                }
            }
            OverflowMenu {
                if !special && !isRecycleBin {
                    Button("Add Person") { toggleManagePeople(participants) }
                }
                if let p = single, contacts.contact(for: p.number) == nil, !isRecycleBin {
                    Button("Add number to contact") { ContactUI.addNumber(p.number) }
                }
                if let p = single {
                    Button("Copy number to clipboard") { store.toast = Launcher.copy(conversation?.phoneNumber ?? p.number) }
                }
                if let c = conversation, c.isGroupConversation, !isRecycleBin {
                    Button("Rename conversation") { rename = c }
                }
                if conversation != nil && !isRecycleBin {
                    Button("Conversation details") { router.push(.details(threadId)) }
                }
                if hasMessages && !isRecycleBin {
                    Button("Mark as Unread") {
                        store.markUnread([threadId])
                        router.pop()
                    }
                }
                if !isRecycleBin {
                    Button("Block number") { askBlock(participants) }
                }
                if hasMessages {
                    Button("Delete", role: .destructive) { askDeleteAll() }
                }
                if hasMessages && isRecycleBin {
                    Button("Restore all messages") {
                        confirm = Confirmation(message: "Are you sure you want to restore all messages of this conversation?") {
                            store.restoreAll(thread: threadId)
                            router.pop()
                        }
                    }
                }
            }
        }
    }

    private func askBlock(_ participants: [Participant]) {
        let numbers = participants.map(\.number)
        confirm = Confirmation(message: "Are you sure you want to block \"\(numbers.joined(separator: ", "))\"?") {
            numbers.forEach(BlockedNumbers.shared.add)
            router.pop()
        }
    }

    private func askDeleteAll() {
        confirm = Confirmation(message: "Are you sure you want to delete all messages of this conversation?") {
            if isRecycleBin { store.emptyRecycleBin(thread: threadId) } else { store.deleteConversations([threadId]) }
            router.pop()
        }
    }

    // MARK: Message list

    private func messageList(_ msgs: [Message]) -> some View {
        let items = threadItems(msgs)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in
                        itemView(item).id(item.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
                    Button {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(palette.surface))
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
            .onAppear {
                if let id = route.searchedMessage {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("m\(id)", anchor: .center) }
                }
            }
            .onChange(of: items.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    /// getThreadItems(): date/time headers 5+ minutes apart, error/sending/sent status rows.
    func threadItems(_ msgs: [Message]) -> [ThreadItem] {
        var items: [ThreadItem] = []
        var prev = 0
        for (i, m) in msgs.enumerated() {
            if m.date - prev > 300 {
                items.append(.dateTime(m.date))
                prev = m.date
            }
            items.append(.message(m))
            if m.type == MessageType.failed { items.append(.error(m)) }
            if m.type == MessageType.outbox { items.append(.sending(m.id)) }
            if i == msgs.count - 1 && m.type == MessageType.sent {
                items.append(.sent(m.id, delivered: m.status == MessageStatus.complete))
            }
        }
        return items
    }

    @ViewBuilder
    private func itemView(_ item: ThreadItem) -> some View {
        switch item {
        case .dateTime(let date):
            Text(formatDateOrTime(date, hideTimeOnOtherDays: false, showCurrentYear: false))
                .font(.system(size: palette.fontSize * 0.8))
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .message(let m):
            MessageBubble(message: m, selected: selection.contains(m.id), onTapAttachment: { a in
                if !selection.isEmpty { toggle(m) } else { open(a) }
            }, onTapSender: {
                if let c = contacts.contact(for: m.senderPhoneNumber) { ContactUI.show(contactId: c.id, lookup: contacts) }
            })
            .contentShape(Rectangle())
            .onTapGesture {
                if !selection.isEmpty { toggle(m) } else if m.isScheduled { scheduledInfo = m }
            }
            .onLongPressGesture { toggle(m) }
        case .error(let m):
            Text("Not sent. Touch to retry.")
                .font(.system(size: palette.fontSize - 4))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    text = m.body
                    attachments = m.attachments
                    messageToResend = m.id
                }
        case .sent(_, let delivered):
            Image(systemName: delivered ? "checkmark.circle.fill" : "checkmark")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
        case .sending:
            Text("Sending…")
                .font(.system(size: palette.fontSize - 4))
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
        }
    }

    private func toggle(_ m: Message) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if selection.contains(m.id) { selection.remove(m.id) } else { selection.insert(m.id) }
    }

    private func open(_ a: Attachment) {
        if Mime.isVCard(a.mimetype) {
            router.push(.vcard(a))
        } else if Mime.isAudio(a.mimetype) {
            AudioPlayback.shared.toggle(a.url)
        } else {
            quickLook = a.url
        }
    }

    // MARK: Action mode (cab_thread)

    private func messagesActionBar(_ msgs: [Message]) -> some View {
        let selected = msgs.filter { selection.contains($0.id) }
        let single = selected.count == 1 ? selected.first : nil
        let hasText = selected.contains { !$0.body.isEmpty }
        let saveable = !selected.isEmpty && selected.allSatisfy { !$0.attachments.isEmpty }
        return ActionModeBar(count: selection.count, onClose: { selection.removeAll() }) {
            if hasText {
                IconButton(icon: "doc.on.doc") {
                    store.toast = Launcher.copy(copyText(selected))
                    selection.removeAll()
                }
            }
            if let m = single, hasText {
                IconButton(icon: "square.and.arrow.up") {
                    shareText = m.body
                    selection.removeAll()
                }
            }
            if saveable {
                IconButton(icon: "square.and.arrow.down") {
                    exportDocs = selected.flatMap(\.attachments).compactMap(AttachmentDocument.init)
                    exporting = !exportDocs.isEmpty
                    selection.removeAll()
                }
            }
            IconButton(icon: "trash") { deleteDialog = true }
            OverflowMenu {
                if let m = single {
                    Button("Forward") {
                        selection.removeAll()
                        router.push(.newConversation(text: m.body, attachments: Array(m.attachments.prefix(1))))
                    }
                }
                if let m = single, hasText {
                    Button("Select text") {
                        selectText = m.body
                        selection.removeAll()
                    }
                }
                Button("Select all") { selection = Set(msgs.map(\.id)) }
                if let m = single {
                    Button("Properties") {
                        details = m
                        selection.removeAll()
                    }
                }
                if isRecycleBin {
                    Button("Restore") {
                        let n = selection.count
                        confirm = Confirmation(message: "Are you sure you want to restore \(n.plural("message", "messages"))?") {
                            store.restoreMessages(selection)
                            selection.removeAll()
                        }
                    }
                }
            }
        }
    }

    /// ThreadAdapter.copyToClipboard(): "[date, time] sender: text" when several are selected.
    private func copyText(_ selected: [Message]) -> String {
        if selected.count == 1 { return selected[0].body }
        let f = DateTimeFormat.shared
        return selected.filter { !$0.body.isEmpty }.map { m in
            let date = DateTimeFormat.format(Date(timeIntervalSince1970: TimeInterval(m.date)), "\(f.dateFormat), \(f.timeFormat)")
            let sender = m.isReceived ? contacts.name(for: m.senderPhoneNumber) : "Me"
            return "[\(date)] \(sender): \(m.body)"
        }.joined(separator: "\n\n")
    }

    func deleteSelected(skipRecycleBin: Bool) {
        let toBin = !skipRecycleBin && config.useRecycleBin && !isRecycleBin
        for id in selection {
            if let m = store.message(id), m.isScheduled { Scheduler.cancel(id) }
        }
        store.deleteMessages(selection, toRecycleBin: toBin)
        selection.removeAll()
    }

    // MARK: Manage people

    private func toggleManagePeople(_ participants: [Participant]) {
        if managePeople {
            managePeople = false
        } else {
            people = participants
            addQuery = ""
            managePeople = true
        }
    }

    private var managePeoplePanel: some View {
        let q = addQuery.trimmingCharacters(in: .whitespaces)
        let suggestions = q.isEmpty ? [] : contacts.contacts.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.numbers.contains { $0.normalizedPhoneNumber.contains(q.normalizedPhoneNumber.isEmpty ? q : q.normalizedPhoneNumber) }
        }.prefix(8)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                FlowChips(people: people, firstNumber: people.first?.number) { p in
                    people.removeAll { $0 == p }
                }
                IconButton(icon: "checkmark") { confirmPeople() }
            }
            HStack {
                TextField("Add Contact or Number…", text: $addQuery)
                    .keyboardType(.default)
                    .autocorrectionDisabled()
                    .onSubmit(addTyped)
                if q.count > 2 {
                    IconButton(icon: "checkmark") { addTyped() }
                }
            }
            ForEach(Array(suggestions)) { c in
                Button {
                    if let n = c.numbers.first { add(Participant(name: c.name, number: n)) }
                } label: {
                    HStack(spacing: 12) {
                        Avatar(name: c.name, image: c.thumbnail, size: 36)
                        VStack(alignment: .leading) {
                            Text(c.name)
                            Text(c.numbers.first ?? "").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func addTyped() {
        let n = addQuery.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        add(Participant(name: contacts.name(for: n), number: n))
    }

    private func add(_ p: Participant) {
        addQuery = ""
        guard !people.contains(where: { $0.number.comparableNumber == p.number.comparableNumber }) else { return }
        people.append(p)
    }

    /// confirmManageContacts: reopen the thread of the new participant set.
    private func confirmPeople() {
        managePeople = false
        let newId = store.threadId(for: people.map(\.number))
        if newId != threadId {
            store.saveDraft(threadId, text)
            router.replaceTop(with: .thread(ThreadRoute(threadId: newId, text: text, attachments: attachments)))
        }
    }

    // MARK: Compose

    private var shortCodeHolder: some View {
        HStack {
            Text("Sender doesn't support replies").font(.system(size: palette.fontSize * 0.9))
            Spacer()
            IconButton(icon: "info.circle") { shortCodeInfo = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(palette.surface.ignoresSafeArea(edges: .bottom))
    }

    private func composeArea(participants: [Participant]) -> some View {
        let mms = isMMS(participants: participants)
        let canSend = !text.isEmpty || !attachments.isEmpty
        let length = SmsLength.calculate(config.useSimpleCharacters ? text.normalizedString : text)
        return VStack(spacing: 0) {
            Divider()
            if isScheduled {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    Button(scheduledDateText) { scheduleDialog = true }
                        .buttonStyle(.plain)
                    Spacer()
                    IconButton(icon: "xmark") {
                        isScheduled = false
                        if let m = scheduledMessage {
                            store.cancelScheduled(m.id)
                            scheduledMessage = nil
                        }
                    }
                }
                .padding(.leading, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.primaryColor.opacity(0.3)))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            if !attachments.isEmpty {
                PendingAttachments(attachments: $attachments)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPicker.toggle()
                        if showPicker { fieldFocused = false }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24))
                        .rotationEffect(.degrees(showPicker ? 45 : 0))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                messageField
                VStack(spacing: 2) {
                    if config.showCharacterCounter {
                        Text("\(length.remaining)/\(length.count)").font(.system(size: 11)).opacity(0.7)
                    }
                    VStack(spacing: 2) {
                        Image(systemName: isScheduled ? "clock.arrow.circlepath" : "paperplane.fill").font(.system(size: 20))
                        Text(mms ? "MMS" : "SMS").font(.system(size: 11, weight: .medium))
                    }
                    .frame(width: 48, height: 44)
                    .contentShape(Rectangle())
                    .opacity(canSend ? 0.9 : 0.4)
                    .onTapGesture { if canSend { sendMessage(participants: participants) } }
                    .onLongPressGesture { if canSend && !isScheduled { scheduleDialog = true } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(isScheduled ? "Schedule send" : "Send SMS")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            if showPicker {
                AttachmentPickerGrid { pick($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(palette.surface.ignoresSafeArea(edges: .bottom))
        .onChange(of: fieldFocused) { _, f in if f { showPicker = false } }
        .onChange(of: text) { _, _ in messageToResend = nil }
    }

    @ViewBuilder
    private var messageField: some View {
        if config.sendOnEnter {
            TextField("Type a message…", text: $text)
                .font(.system(size: palette.fontSize))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .focused($fieldFocused)
                .onSubmit { sendMessage(participants: store.participants(threadId, contacts: contacts)) }
                .padding(.vertical, 11)
        } else {
            TextField("Type a message…", text: $text, axis: .vertical)
                .font(.system(size: palette.fontSize))
                .lineLimit(1...6)
                .focused($fieldFocused)
                .padding(.vertical, 11)
        }
    }

    private var scheduledDateText: String {
        let cal = Calendar.current
        if cal.component(.year, from: scheduledDate) > cal.component(.year, from: Date()) {
            return DateTimeFormat.shared.format(scheduledDate)
        }
        return DateTimeFormat.format(scheduledDate, "MMM d, \(DateTimeFormat.shared.timeFormat)")
    }

    /// isMmsMessage(): attachments, group MMS or long messages sent as MMS.
    func isMMS(participants: [Participant]) -> Bool {
        let isGroupMms = participants.count > 1 && config.sendGroupMessageMMS
        let isLong = config.sendLongMessageMMS && SmsLength.calculate(text).count > 1
        return !attachments.isEmpty || isGroupMms || isLong
    }

    private func pick(_ action: PickerAction) {
        switch action {
        case .choosePhoto: photoPicker = true
        case .chooseVideo: videoPicker = true
        case .takePhoto: camera = false
        case .recordVideo: camera = true
        case .recordAudio: recorder = true
        case .chooseFile: filePicker = true
        case .chooseContact: contactPicker = true
        case .schedule: if !isScheduled { scheduleDialog = true }
        }
    }

    /// addAttachment(): duplicate and MMS size checks, image compression.
    func addAttachment(data: Data, mimetype: String, filename: String) {
        if attachments.contains(where: { $0.filename == filename && (try? Data(contentsOf: $0.url).count) == data.count }) {
            store.toast = "Duplicate item was not included"
            return
        }
        var data = data
        var mime = mimetype
        var name = filename
        let limit = config.mmsFileSizeLimit
        if Mime.isImage(mime) && !Mime.isGif(mime) {
            if let compressed = AttachmentFiles.compressImage(data, limit: limit) {
                data = compressed
                mime = "image/jpeg"
                name = (name as NSString).deletingPathExtension + ".jpg"
            }
        } else if limit != FileSize.none && Int64(data.count) > limit {
            store.toast = "Attachment size exceeds max MMS limit"
            return
        }
        do {
            attachments.append(try AttachmentFiles.save(data, mimetype: mime, filename: name))
            showPicker = false
        } catch {
            store.toast = "An unknown error occurred"
        }
    }

    // MARK: Sending

    func sendMessage(participants: [Participant]) {
        var body = text
        guard !body.isEmpty || !attachments.isEmpty else {
            store.toast = "An unknown error occurred"
            return
        }
        guard !participants.isEmpty else {
            store.toast = "Add a recipient first"
            return
        }
        if config.useSimpleCharacters { body = body.normalizedString }
        if isScheduled {
            sendScheduled(body, participants: participants)
        } else if !confirmGroupMessageSendIfNeeded(participants) {
            sendNormal(body, participants: participants)
        }
    }

    /// GroupMessageSendDialog, asked once.
    private func confirmGroupMessageSendIfNeeded(_ participants: [Participant]) -> Bool {
        guard !config.isGroupMessageMmsPreferenceResolved, Set(participants.map(\.number)).count >= 2 else { return false }
        groupSendDialog = true
        return true
    }

    func sendNormal(_ body: String, participants: [Participant]) {
        let sentText = text
        let sentAttachments = attachments
        let request = ComposeRequest(
            recipients: participants.map(\.number),
            names: Dictionary(participants.map { ($0.number, $0.name) }, uniquingKeysWith: { a, _ in a }),
            body: body, attachments: sentAttachments, threadId: threadId, isMMS: isMMS(participants: participants),
            separately: participants.count > 1 && !config.sendGroupMessageMMS, replacing: messageToResend,
            onFinish: { sent in
                if !sent && text.isEmpty && attachments.isEmpty {
                    text = sentText
                    attachments = sentAttachments
                }
            })
        text = ""
        attachments = []
        messageToResend = nil
        store.saveDraft(threadId, "")
        store.send(request)
    }

    private func sendScheduled(_ body: String, participants: [Participant]) {
        guard scheduledDate.timeIntervalSinceNow > 1 else {
            store.toast = "You must pick a time in the future"
            scheduleDialog = true
            return
        }
        if confirmGroupMessageSendIfNeeded(participants) { return }
        let id = scheduledMessage?.id ?? store.newId()
        let m = Message(
            id: id, body: body, type: MessageType.queued, status: MessageStatus.none, participants: participants,
            date: Int(scheduledDate.timeIntervalSince1970), read: false, threadId: threadId,
            isMMS: isMMS(participants: participants), attachments: attachments, senderPhoneNumber: "", senderName: "",
            subscriptionId: -1, isScheduled: true)
        store.schedule(m, title: participants.map(\.name).joined(separator: ", "))
        text = ""
        attachments = []
        isScheduled = false
        scheduledMessage = nil
        store.saveDraft(threadId, "")
    }

    /// showScheduledMessageInfo() actions.
    func handleScheduled(_ m: Message, action: Int) {
        switch action {
        case 0:  // Update message
            scheduledMessage = m
            text = m.body
            attachments = m.attachments
            scheduledDate = Date(timeIntervalSince1970: TimeInterval(m.date))
            isScheduled = true
        case 1:  // Send now
            let addresses = store.threads[threadId]?.addresses ?? m.participants.map(\.number)
            store.send(ComposeRequest(recipients: addresses, body: m.body, attachments: m.attachments,
                                      threadId: threadId, isMMS: m.isMMS, replacing: m.id))
        default:
            store.cancelScheduled(m.id)
        }
    }
}

/// Selected contacts as removable chips (item_selected_contact); the first one stays.
struct FlowChips: View {
    @Environment(\.palette) private var palette
    let people: [Participant]
    let firstNumber: String?
    let onRemove: (Participant) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(people, id: \.number) { p in
                    HStack(spacing: 4) {
                        Text(p.name).lineLimit(1)
                        if p.number != firstNumber {
                            Button { onRemove(p) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(palette.onPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(palette.primaryColor))
                }
            }
        }
    }
}

/// "Save as": an attachment for the system file exporter.
struct AttachmentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    var filename: String

    init?(_ a: Attachment) {
        guard let d = try? Data(contentsOf: a.url) else { return nil }
        data = d
        filename = a.filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        filename = configuration.file.filename ?? "attachment"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let w = FileWrapper(regularFileWithContents: data)
        w.preferredFilename = filename
        return w
    }
}

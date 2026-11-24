import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// RenameConversationDialog.
struct RenameConversationDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(MessagesStore.self) private var store
    let conversation: Conversation
    let onRename: (String) -> Void
    @State private var name: String
    @FocusState private var focused: Bool

    init(conversation: Conversation, onRename: @escaping (String) -> Void) {
        self.conversation = conversation
        self.onRename = onRename
        _name = State(initialValue: conversation.usesCustomTitle ? conversation.title : "")
    }

    var body: some View {
        DialogFrame(title: "Rename conversation", scroll: false) {
            TextField(conversation.title, text: $name)
                .focused($focused)
                .padding(.vertical, 8)
            Divider().overlay(palette.primaryColor)
            Text("Only you can see this conversation name").font(.system(size: 13)).foregroundStyle(palette.secondaryText).padding(.top, 6)
            DialogButtons {
                if name.isEmpty {
                    store.toast = "Please enter a name"
                    return
                }
                onRename(name)
                dismiss()
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}

/// DeleteConfirmationDialog: optional "skip the recycle bin" checkbox.
struct DeleteConfirmationDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let message: String
    let showSkipRecycleBin: Bool
    let onConfirm: (Bool) -> Void
    @State private var skip = false

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            Text(message).font(.system(size: 16)).padding(.bottom, 8)
            if showSkipRecycleBin {
                CheckRow(title: "Skip the Recycle Bin, delete messages directly", on: $skip)
            }
            HStack(spacing: 24) {
                Spacer()
                Button("No") { dismiss() }
                Button("Yes") {
                    dismiss()
                    onConfirm(skip)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(palette.primaryColor)
            .padding(.top, 16)
        }
        .presentationDetents([.height(showSkipRecycleBin ? 240 : 190)])
    }
}

/// MessageDetailsDialog (BasePropertiesDialog).
struct MessageDetailsDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(ContactsLookup.self) private var contacts
    let message: Message

    var body: some View {
        let m = message
        DialogFrame(title: "Message details", scroll: false) {
            property(m.isReceived ? "Sender" : "Receiver", people)
            property(m.isReceived ? "Received at" : "Sent at",
                     DateTimeFormat.format(Date(timeIntervalSince1970: TimeInterval(m.date)),
                                           "\(DateTimeFormat.shared.dateFormat) \(timeFormatWithSeconds)"))
            HStack {
                Spacer()
                Button("OK") { dismiss() }.font(.system(size: 16, weight: .medium)).foregroundStyle(palette.primaryColor)
            }
            .padding(.top, 16)
        }
        .presentationDetents([.medium])
    }

    private var people: String {
        func info(_ name: String, _ number: String) -> String { name != number ? "\(name) (\(number))" : number }
        if message.isReceived {
            return info(contacts.name(for: message.senderPhoneNumber), message.senderPhoneNumber)
        }
        return message.participants.map { info(contacts.name(for: $0.number), $0.number) }.joined(separator: ", ")
    }

    private func property(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 14, weight: .bold))
            Text(value).font(.system(size: 15)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// SelectTextDialog.
struct SelectTextDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        DialogFrame(title: nil) {
            Text(text).font(.system(size: palette.fontSize)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
                Button("OK") { dismiss() }.font(.system(size: 16, weight: .medium)).foregroundStyle(palette.primaryColor)
            }
            .padding(.top, 16)
        }
    }
}

/// GroupMessageSendDialog.
struct GroupMessageSendDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onChoice: (Bool) -> Void

    var body: some View {
        DialogFrame(title: "Group message format", scroll: false) {
            Text("Group MMS keeps replies in one conversation, but carrier charges may apply. Sending separately sends one message to each person. You can change this later in app settings.")
                .font(.system(size: 15))
            HStack(spacing: 24) {
                Spacer()
                Button("Send separately") { choose(false) }
                Button("Group MMS") { choose(true) }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(palette.primaryColor)
            .padding(.top, 16)
        }
        .presentationDetents([.medium])
    }

    private func choose(_ group: Bool) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onChoice(group) }
    }
}

/// ExportMessagesDialog: SMS/MMS checkboxes and the file name; the system picker saves it.
struct ExportMessagesDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    @Environment(MessagesStore.self) private var store
    let onExport: (URL) -> Void
    @State private var sms = Config.shared.exportSms
    @State private var mms = Config.shared.exportMms
    @State private var name = "Messages_\(currentFormattedDateTime())"

    var body: some View {
        DialogFrame(title: "Export messages", scroll: false) {
            CheckRow(title: "Export SMS", on: $sms)
            CheckRow(title: "Export MMS", on: $mms)
            Text("Filename").font(.system(size: 13)).foregroundStyle(palette.primaryColor).padding(.top, 8)
            TextField("", text: $name).autocorrectionDisabled().padding(.vertical, 8)
            Divider().overlay(palette.primaryColor)
            DialogButtons { export() }
        }
        .presentationDetents([.medium])
    }

    private func export() {
        config.exportSms = sms
        config.exportMms = mms
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { store.toast = "Please enter a name"; return }
        guard n.isAValidFilename else { store.toast = "The name contains invalid characters"; return }
        let list = MessagesBackupIO.export(store, sms: sms, mms: mms)
        guard !list.isEmpty else {
            store.toast = "No entries for exporting have been found"
            dismiss()
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(n + ".json")
            try MessagesBackupIO.encode(list).write(to: url, options: .atomic)
            dismiss()
            onExport(url)
        } catch {
            store.toast = "Exporting failed"
        }
    }
}

/// ImportMessagesDialog: parses the file, then SMS/MMS checkboxes.
struct ImportMessagesDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    let url: URL
    @State private var backups: [MessagesBackup]?
    @State private var sms = Config.shared.importSms
    @State private var mms = Config.shared.importMms
    @State private var importing = false

    var body: some View {
        DialogFrame(title: "Import messages", scroll: false) {
            if let backups {
                if backups.contains(where: \.isSms) { CheckRow(title: "Import SMS", on: $sms) }
                if backups.contains(where: { !$0.isSms }) { CheckRow(title: "Import MMS", on: $mms) }
                if importing { ProgressView().tint(palette.primaryColor).frame(maxWidth: .infinity).padding(.top, 8) }
                DialogButtons(okEnabled: !importing) { start(backups) }
            } else {
                ProgressView().tint(palette.primaryColor).frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(importing)
        .task { load() }
    }

    private func load() {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let list = try MessagesBackupIO.parse(data)
            if list.isEmpty {
                store.toast = "No entries for importing have been found"
                dismiss()
            } else {
                backups = list
            }
        } catch {
            store.toast = "Invalid file format"
            dismiss()
        }
    }

    private func start(_ list: [MessagesBackup]) {
        guard sms || mms else {
            store.toast = "You have to select at least one item"
            return
        }
        importing = true
        store.toast = "Importing…"
        config.importSms = sms
        config.importMms = mms
        Task { @MainActor in
            let result = MessagesBackupIO.restore(list, into: store, contacts: contacts)
            store.toast = switch result {
            case .ok: "Importing successful"
            case .partial: "Importing some entries failed"
            case .fail: "Importing failed"
            case .nothingNew: "No items found."
            }
            dismiss()
        }
    }
}

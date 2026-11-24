import FossifyCommons
import SwiftUI
import UIKit

/// NewConversationActivity.
struct NewConversationView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    /// Forwarded text / attachments (Intent.ACTION_SEND).
    let text: String?
    let attachments: [Attachment]
    @State private var address = ""
    @State private var choose: SimpleContact?
    @FocusState private var focused: Bool

    var body: some View {
        let q = address.trimmingCharacters(in: .whitespaces)
        let list = filtered(q)
        VStack(spacing: 0) {
            TopBar(title: "New conversation")
            HStack {
                TextField("Add Contact or Number…", text: $address)
                    .font(.system(size: palette.fontSize))
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { if q.count > 2 { confirm(q) } }
                if q.count > 2 {
                    IconButton(icon: "checkmark") { confirm(q) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let suggestions = store.suggestedContacts(contacts: contacts)
                        if q.isEmpty && !suggestions.isEmpty {
                            Text("Suggestions").sectionHeader(palette)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(suggestions) { c in
                                        Button { open(c.numbers[0], name: c.name) } label: {
                                            VStack(spacing: 6) {
                                                Avatar(name: c.name, image: c.thumbnail, size: 56)
                                                Text(c.name).font(.system(size: 13)).lineLimit(1).frame(width: 72)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        if list.isEmpty {
                            placeholder.padding(.top, 40)
                        }
                        ForEach(list) { c in
                            Button { pick(c) } label: { row(c) }
                                .buttonStyle(.plain)
                                .id(c.id)
                        }
                    }
                    .padding(.bottom, 32)
                }
                .overlay(alignment: .trailing) {
                    let letters = Self.letters(list)
                    if letters.count > 1 && q.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(letters, id: \.self) { l in
                                Text(l).font(.system(size: 11, weight: .medium)).frame(width: 22, height: 15)
                                    .onTapGesture {
                                        if let c = list.first(where: { Self.letter($0.name) == l }) { proxy.scrollTo(c.id, anchor: .top) }
                                    }
                            }
                        }
                        .padding(.trailing, 2)
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear { focused = true }
        .sheet(item: $choose) { c in
            RadioDialog(title: nil, items: c.numbers.map { ($0, $0) }, selected: "") { open($0, name: c.name) }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if contacts.access == .denied {
            Placeholder(text: "The app could not access your contacts", action: "Request the required permissions") {
                Launcher.open(URL(string: UIApplication.openSettingsURLString))
            }
        } else {
            Placeholder(text: "No contacts found")
        }
    }

    private func row(_ c: SimpleContact) -> some View {
        HStack(spacing: 14) {
            Avatar(name: c.name, image: c.thumbnail, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.system(size: palette.fontSize)).lineLimit(1)
                Text(c.numbers.first ?? "").font(.system(size: palette.fontSize * 0.8)).foregroundStyle(palette.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// Contacts whose name or number matches, names starting with the text first.
    private func filtered(_ q: String) -> [SimpleContact] {
        guard !q.isEmpty else { return contacts.contacts }
        let digits = q.normalizedPhoneNumber
        let list = contacts.contacts.filter { c in
            (!digits.isEmpty && c.numbers.contains { $0.normalizedPhoneNumber.contains(digits) })
                || c.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return list.filter { $0.name.lowercased().hasPrefix(q.lowercased()) } + list.filter { !$0.name.lowercased().hasPrefix(q.lowercased()) }
    }

    static func letter(_ name: String) -> String { String(name.prefix(1)).uppercased().normalizedString }

    static func letters(_ list: [SimpleContact]) -> [String] {
        var seen = Set<String>()
        return list.map { letter($0.name) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func pick(_ c: SimpleContact) {
        if c.numbers.count == 1 { open(c.numbers[0], name: c.name) } else { choose = c }
    }

    private func confirm(_ number: String) {
        if number.isShortCodeWithLetters {
            address = ""
            store.toast = "Can't reply to short codes like this"
            return
        }
        open(number, name: number)
    }

    /// launchThreadActivity(): numbers separated by ';' start a group conversation.
    private func open(_ number: String, name: String) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let numbers = number.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let id = store.threadId(for: numbers)
        router.push(.thread(ThreadRoute(threadId: id, text: text, attachments: attachments)))
    }
}

/// ConversationDetailsActivity.
struct ConversationDetailsView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(\.palette) private var palette
    let threadId: Int64
    @State private var rename: Conversation?

    var body: some View {
        let conversation = store.conversation(threadId, contacts: contacts)
        let participants = store.participants(threadId, contacts: contacts)
        VStack(spacing: 0) {
            TopBar(title: "Conversation details")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let c = conversation {
                        Text("Conversation name").sectionHeader(palette)
                        Button { rename = c } label: {
                            HStack {
                                Text(c.title).font(.system(size: 16))
                                Spacer()
                                Image(systemName: "pencil")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    Text("Members").sectionHeader(palette)
                    ForEach(participants, id: \.number) { p in
                        Button {
                            if let c = contacts.contact(for: p.number) { ContactUI.show(contactId: c.id, lookup: contacts) }
                        } label: {
                            HStack(spacing: 14) {
                                Avatar(name: p.name, image: contacts.photo(for: p.number), size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: palette.fontSize))
                                    if p.name != p.number {
                                        Text(p.number).font(.system(size: palette.fontSize * 0.8)).foregroundStyle(palette.secondaryText)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(item: $rename) { c in
            RenameConversationDialog(conversation: c) { store.rename(c.threadId, to: $0) }
        }
    }
}

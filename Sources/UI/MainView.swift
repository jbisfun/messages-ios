import FossifyCommons
import SwiftUI
import UIKit

/// MainActivity: conversations, search, action mode.
struct MainView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var selection = Set<Int64>()
    @State private var confirm: Confirmation?
    @State private var rename: Conversation?

    var body: some View {
        let conversations = sorted(store.conversations(archived: false, contacts: contacts))
        VStack(spacing: 0) {
            if selection.isEmpty {
                searchBar
            } else {
                ConversationsActionBar(conversations: conversations, selection: $selection, confirm: $confirm, rename: $rename)
            }
            ZStack(alignment: .bottomTrailing) {
                if searching && !query.isEmpty {
                    SearchResultsView(query: query)
                } else if conversations.isEmpty {
                    Placeholder(text: "No stored conversations have been found", action: "Start a conversation") {
                        router.push(.newConversation(text: nil, attachments: []))
                    }
                } else {
                    ConversationsList(conversations: conversations, selection: $selection) { c in
                        router.push(.thread(ThreadRoute(threadId: c.threadId)))
                    }
                }
                if selection.isEmpty && !(searching && !query.isEmpty) {
                    Fab(icon: "plus.message") { router.push(.newConversation(text: nil, attachments: [])) }
                        .padding(16)
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .confirmation($confirm)
        .sheet(item: $rename) { c in
            RenameConversationDialog(conversation: c) { title in
                store.rename(c.threadId, to: title)
                selection.removeAll()
            }
        }
    }

    /// Pinned first, then newest (setupConversations()).
    private func sorted(_ list: [Conversation]) -> [Conversation] {
        list.sorted {
            let p0 = config.isPinned($0.threadId), p1 = config.isPinned($1.threadId)
            if p0 != p1 { return p0 }
            return $0.date > $1.date
        }
    }

    // MARK: Search menu (MySearchMenu)

    private var searchBar: some View {
        HStack(spacing: 0) {
            if !searching { CloseAppButton() }
            Button {
                if searching {
                    query = ""
                    searching = false
                    searchFocused = false
                } else {
                    searching = true
                    searchFocused = true
                }
            } label: {
                Image(systemName: searching ? "arrow.left" : "magnifyingglass").font(.system(size: 18)).frame(width: 48, height: 48)
            }
            TextField("", text: $query, prompt: Text("Search").foregroundStyle(palette.secondaryText))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: searchFocused) { _, f in if f { searching = true } }
            if !query.isEmpty {
                IconButton(icon: "xmark") { query = "" }
            }
            OverflowMenu {
                if config.useRecycleBin {
                    Button { router.push(.recycleBin) } label: { Label("Show the recycle bin", systemImage: "trash") }
                }
                if config.isArchiveAvailable {
                    Button { router.push(.archived) } label: { Label("Show archived conversations", systemImage: "archivebox") }
                }
                Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
                Button { router.push(.about) } label: { Label("About", systemImage: "info.circle") }
            }
        }
        .foregroundStyle(palette.textColor)
        .background(Capsule().fill(palette.surface))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// search_holder: results for 2+ characters (SearchResultsAdapter).
struct SearchResultsView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    let query: String

    var body: some View {
        if query.count < 2 {
            Placeholder(text: "Type in at least 2 characters to start the search.")
        } else {
            let results = store.search(query, contacts: contacts)
            if results.isEmpty {
                Placeholder(text: "No items found.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { r in
                            Button {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                router.push(.thread(ThreadRoute(threadId: r.threadId, searchedMessage: r.messageId == -1 ? nil : r.messageId)))
                            } label: {
                                row(r)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func row(_ r: SearchResult) -> some View {
        HStack(spacing: 14) {
            Avatar(name: r.title, image: contacts.photo(for: r.number), size: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(highlighted(r.title, query, color: palette.primaryColor)).font(.system(size: palette.fontSize * 1.05)).lineLimit(1)
                    Spacer()
                    Text(r.date).font(.system(size: palette.fontSize * 0.75)).opacity(0.7)
                }
                Text(highlighted(r.snippet, query, color: palette.primaryColor))
                    .font(.system(size: palette.fontSize * 0.85)).lineLimit(2).opacity(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// cab_conversations (ConversationsAdapter).
struct ConversationsActionBar: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    let conversations: [Conversation]
    @Binding var selection: Set<Int64>
    @Binding var confirm: Confirmation?
    @Binding var rename: Conversation?

    var body: some View {
        let selected = conversations.filter { selection.contains($0.threadId) }
        let single = selected.count == 1 ? selected.first : nil
        let singlePerson = single.flatMap { $0.isGroupConversation ? nil : $0 }
        let pinned = config.pinnedConversations
        ActionModeBar(count: selection.count, onClose: { selection.removeAll() }) {
            if selected.contains(where: { !pinned.contains(String($0.threadId)) }) {
                IconButton(icon: "pin") { pin(true) }
            }
            if !selected.isEmpty && selected.allSatisfy({ pinned.contains(String($0.threadId)) }) {
                IconButton(icon: "pin.slash") { pin(false) }
            }
            if let c = singlePerson, !c.phoneNumber.isShortCodeWithLetters {
                IconButton(icon: "phone") {
                    Launcher.call(c.phoneNumber)
                    selection.removeAll()
                }
            }
            if config.isArchiveAvailable {
                IconButton(icon: "archivebox") { askArchive() }
            }
            IconButton(icon: "trash") { askDelete() }
            OverflowMenu {
                Button("Select all") { selection = Set(conversations.map(\.threadId)) }
                if selected.contains(where: { !$0.read }) {
                    Button("Mark as Read") { store.markRead(selection); selection.removeAll() }
                }
                if selected.contains(where: \.read) {
                    Button("Mark as Unread") { store.markUnread(selection); selection.removeAll() }
                }
                if let c = singlePerson {
                    Button("Add number to contact") { ContactUI.addNumber(c.phoneNumber); selection.removeAll() }
                    Button("Copy number to clipboard") {
                        store.toast = Launcher.copy(c.phoneNumber)
                        selection.removeAll()
                    }
                }
                if let c = single, c.isGroupConversation {
                    Button("Rename conversation") { rename = c }
                }
                if let c = single {
                    Button("Conversation details") {
                        selection.removeAll()
                        router.push(.details(c.threadId))
                    }
                }
                Button("Block number") { askBlock(selected) }
            }
        }
    }

    private func pin(_ on: Bool) {
        let ids = selection.map(String.init)
        if on { config.pinnedConversations.formUnion(ids) } else { config.pinnedConversations.subtract(ids) }
        selection.removeAll()
    }

    private func askDelete() {
        let n = selection.count
        confirm = Confirmation(message: "Are you sure you want to delete \(n.plural("conversation", "conversations"))?") {
            store.deleteConversations(selection)
            selection.removeAll()
        }
    }

    private func askArchive() {
        let n = selection.count
        confirm = Confirmation(message: "Are you sure you want to archive \(n.plural("conversation", "conversations"))?") {
            store.setArchived(selection, true)
            selection.removeAll()
        }
    }

    private func askBlock(_ selected: [Conversation]) {
        var seen = Set<String>()
        let numbers = selected.map(\.phoneNumber).filter { seen.insert($0).inserted }
        confirm = Confirmation(message: "Are you sure you want to block \"\(numbers.joined(separator: ", "))\"?") {
            numbers.forEach(BlockedNumbers.shared.add)
            selection.removeAll()
        }
    }
}

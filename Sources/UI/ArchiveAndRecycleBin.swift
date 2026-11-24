import FossifyCommons
import SwiftUI

/// ArchivedConversationsActivity.
struct ArchivedConversationsView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @State private var selection = Set<Int64>()
    @State private var confirm: Confirmation?

    var body: some View {
        let list = store.conversations(archived: true, contacts: contacts).sorted { $0.date > $1.date }
        VStack(spacing: 0) {
            if selection.isEmpty {
                TopBar(title: "Archive") {
                    OverflowMenu {
                        Button("Delete all archived conversations", role: .destructive) {
                            confirm = Confirmation(message: "Are you sure you want to empty the archive? All archived conversations will be permanently lost.") {
                                store.emptyArchive()
                                store.toast = "The archive has been emptied successfully"
                            }
                        }
                    }
                }
            } else {
                // cab_archived_conversations
                ActionModeBar(count: selection.count, onClose: { selection.removeAll() }) {
                    IconButton(icon: "tray.and.arrow.up") {
                        store.setArchived(selection, false)
                        selection.removeAll()
                    }
                    IconButton(icon: "trash") {
                        let n = selection.count
                        confirm = Confirmation(message: "Are you sure you want to delete \(n.plural("conversation", "conversations"))?") {
                            store.deleteConversations(selection)
                            selection.removeAll()
                        }
                    }
                    IconButton(icon: "checklist") { selection = Set(list.map(\.threadId)) }
                }
            }
            if list.isEmpty {
                Placeholder(text: "No archived conversations have been found")
            } else {
                ConversationsList(conversations: list, selection: $selection) { c in
                    router.push(.thread(ThreadRoute(threadId: c.threadId)))
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .confirmation($confirm)
    }
}

/// RecycleBinConversationsActivity.
struct RecycleBinConversationsView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Router.self) private var router
    @Environment(\.palette) private var palette
    @State private var selection = Set<Int64>()
    @State private var confirm: Confirmation?

    var body: some View {
        let list = store.recycleBinConversations(contacts: contacts)
        VStack(spacing: 0) {
            if selection.isEmpty {
                TopBar(title: "Recycle bin") {
                    IconButton(icon: "trash") {
                        if store.recycleBinCount == 0 {
                            store.toast = "The recycle bin is empty"
                        } else {
                            confirm = Confirmation(message: "Are you sure you want to empty the Recycle Bin? The messages will be permanently lost.") {
                                store.emptyRecycleBin()
                                store.toast = "The recycle bin has been emptied successfully"
                            }
                        }
                    }
                }
            } else {
                // cab_recycle_bin_conversations
                ActionModeBar(count: selection.count, onClose: { selection.removeAll() }) {
                    IconButton(icon: "trash") {
                        let n = selection.count
                        confirm = Confirmation(message: "Are you sure you want to delete \(n.plural("conversation", "conversations"))?") {
                            selection.forEach { store.emptyRecycleBin(thread: $0) }
                            selection.removeAll()
                        }
                    }
                    OverflowMenu {
                        Button("Restore all messages") {
                            let n = selection.count
                            confirm = Confirmation(message: "Are you sure you want to restore \(n.plural("conversation", "conversations"))?") {
                                selection.forEach { store.restoreAll(thread: $0) }
                                selection.removeAll()
                            }
                        }
                        Button("Select all") { selection = Set(list.map(\.threadId)) }
                    }
                }
            }
            if list.isEmpty {
                Placeholder(text: "The recycle bin is empty")
            } else {
                ConversationsList(conversations: list, selection: $selection) { c in
                    router.push(.thread(ThreadRoute(threadId: c.threadId, isRecycleBin: true)))
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .confirmation($confirm)
    }
}

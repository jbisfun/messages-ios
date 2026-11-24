import FossifyCommons
import Observation
import SwiftUI
import UIKit

/// ThreadActivity extras.
struct ThreadRoute: Hashable {
    var threadId: Int64
    var searchedMessage: Int64?
    var isRecycleBin = false
    /// THREAD_TEXT / THREAD_ATTACHMENT_URI(S): prefilled text and attachments.
    var text: String?
    var attachments: [Attachment] = []
}

enum Route: Hashable {
    case thread(ThreadRoute)
    /// NewConversationActivity, optionally with text/attachments to forward.
    case newConversation(text: String?, attachments: [Attachment])
    case details(Int64)
    case archived
    case recycleBin
    case blockedNumbers
    case blockedKeywords
    case vcard(Attachment)
    case settings
    case customizeColors
    case about
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }

    /// Replaces the current screen (ThreadActivity relaunching itself with new participants,
    /// NewConversationActivity finishing after opening a thread).
    func replaceTop(with r: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(r)
    }
}

/// The whole app as one view: the standalone app's window content, and what the
/// launcher presents. `importURL` is a backup (.json/.xml) handed over by the launcher.
public struct MessagesRoot: View {
    @State private var store = MessagesStore()
    @State private var contacts = ContactsLookup()
    @State private var router = Router()
    private let importURL: URL?

    public init(importURL: URL? = nil) {
        self.importURL = importURL
    }

    public var body: some View {
        RootView(importURL: importURL)
            .environment(store)
            .environment(contacts)
            .environment(router)
            .environment(Config.shared)
            .appLock()
            .fossifyTheme()
    }
}

struct RootView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var phase
    let importURL: URL?
    @State private var openedURL: URL?

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        NavigationStack(path: $router.path) {
            MainView()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
                .toolbar(.hidden, for: .navigationBar)
        }
        .toast($store.toast)
        .sheet(item: Binding(get: { openedURL.map(IdentifiedURL.init) }, set: { openedURL = $0?.url })) { item in
            ImportMessagesDialog(url: item.url)
        }
        .onOpenURL { openedURL = $0 }
        .onAppear {
            if let importURL { openedURL = importURL }
            contacts.requestAccess()
            store.checkAndDeleteOldRecycleBinMessages()
            sendDueScheduled()
        }
        .onChange(of: phase) { _, p in
            guard p == .active else { return }
            contacts.reload()
            sendDueScheduled()
        }
        .onChange(of: store.composeQueue.count) { _, _ in MessageComposer.shared.presentNext(store) }
        .onDisappear { store.writeNow() }
    }

    /// ScheduledMessageReceiver: due scheduled messages go to the composer.
    private func sendDueScheduled() {
        for m in store.dueScheduled where !store.composeQueue.contains(where: { $0.replacing == m.id }) {
            let addresses = store.threads[m.threadId]?.addresses ?? m.participants.map(\.number)
            store.send(ComposeRequest(recipients: addresses, body: m.body, attachments: m.attachments,
                                      threadId: m.threadId, isMMS: m.isMMS, replacing: m.id))
        }
    }
}

/// The screen behind each route, with the hidden system navigation bar.
struct RouteView: View {
    let route: Route

    var body: some View {
        destination
            .toolbar(.hidden, for: .navigationBar)
            .paletteBackground()
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .thread(let r): ThreadView(route: r).id(r)
        case .newConversation(let text, let attachments): NewConversationView(text: text, attachments: attachments)
        case .details(let id): ConversationDetailsView(threadId: id)
        case .archived: ArchivedConversationsView()
        case .recycleBin: RecycleBinConversationsView()
        case .blockedNumbers: ManageBlockedNumbersView()
        case .blockedKeywords: ManageBlockedKeywordsView()
        case .vcard(let a): VCardViewerView(attachment: a)
        case .settings: SettingsView()
        case .customizeColors: CustomizeColorsView()
        case .about: AboutView(app: .messages)
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

import FossifyCommons
import SwiftUI
import UIKit

/// org.fossify.commons.helpers.letterBackgroundColors (ARGB).
let letterBackgroundColors: [UInt32] = [
    0xCCD32F2F, 0xCCC2185B, 0xCC1976D2, 0xCC0288D1, 0xCC0097A7,
    0xCC00796B, 0xCC388E3C, 0xCC689F38, 0xCCF57C00, 0xCCE64A19,
]

/// Round contact image, letter placeholder or group icon (SimpleContactsHelper).
struct Avatar: View {
    let name: String
    var image: Data?
    var size: CGFloat = 48
    var isGroup = false

    var body: some View {
        if let image, let ui = UIImage(data: image) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let idx = Int(abs(Int64(name.javaHashCode)) % Int64(letterBackgroundColors.count))
            ZStack {
                Circle().fill(Color(argb: letterBackgroundColors[idx]))
                if isGroup {
                    Image(systemName: "person.2.fill").font(.system(size: size * 0.38)).foregroundStyle(.white)
                } else {
                    Text(name.nameLetter).font(.system(size: size * 0.45)).foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

/// MyFloatingActionButton.
struct Fab: View {
    @Environment(\.palette) private var palette
    var icon = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(palette.primaryColor))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Placeholder text with an optional underlined action below it.
struct Placeholder: View {
    @Environment(\.palette) private var palette
    let text: String
    var action: String?
    var onAction: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.system(size: 17).italic())
                .foregroundStyle(palette.textColor)
                .multilineTextAlignment(.center)
            if let action {
                Button(action: onAction) {
                    Text(action).font(.system(size: 17)).underline().foregroundStyle(palette.primaryColor)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// item_conversation.
struct ConversationRow: View {
    @Environment(\.palette) private var palette
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Config.self) private var config
    let conversation: Conversation
    var draft: String?
    var selected = false

    var body: some View {
        let c = conversation
        let fs = palette.fontSize
        let weight: Font.Weight = c.read ? .regular : .bold
        HStack(spacing: 14) {
            Avatar(name: c.title, image: c.isGroupConversation ? nil : contacts.photo(for: c.phoneNumber), size: 50,
                   isGroup: c.isGroupConversation)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.title)
                        .font(.system(size: fs * 1.05, weight: weight))
                        .italic(c.isScheduled)
                        .lineLimit(1)
                    if config.isPinned(c.threadId) {
                        Image(systemName: "pin.fill").font(.system(size: fs * 0.7)).rotationEffect(.degrees(45))
                    }
                    Spacer(minLength: 4)
                    Text(formatDateOrTime(c.date, hideTimeOnOtherDays: true, showCurrentYear: false))
                        .font(.system(size: fs * 0.75, weight: weight))
                        .italic(c.isScheduled)
                        .opacity(c.read ? 0.7 : 1)
                }
                HStack(spacing: 6) {
                    Group {
                        if let draft, !draft.isEmpty {
                            Text("Draft ").foregroundStyle(palette.primaryColor).italic() + Text(draft)
                        } else {
                            Text(c.snippet)
                        }
                    }
                    .font(.system(size: fs * 0.85, weight: weight))
                    .italic(c.isScheduled)
                    .lineLimit(2)
                    .opacity(c.read ? 0.7 : 1)
                    Spacer(minLength: 4)
                    if !c.read {
                        Text(c.unreadCount > 99 ? "99+" : (c.unreadCount == 0 ? "" : "\(c.unreadCount)"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.onPrimary)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(palette.primaryColor))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selected ? palette.primaryColor.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
    }
}

/// Conversations list with selection (BaseConversationsAdapter).
struct ConversationsList: View {
    @Environment(MessagesStore.self) private var store
    let conversations: [Conversation]
    @Binding var selection: Set<Int64>
    let onClick: (Conversation) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(conversations) { c in
                    ConversationRow(conversation: c, draft: store.draft(c.threadId), selected: selection.contains(c.threadId))
                        .onTapGesture {
                            if selection.isEmpty { onClick(c) } else { toggle(c) }
                        }
                        .onLongPressGesture { toggle(c) }
                }
            }
            .padding(.bottom, 90)
        }
    }

    private func toggle(_ c: Conversation) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if selection.contains(c.threadId) { selection.remove(c.threadId) } else { selection.insert(c.threadId) }
    }
}

/// ConfirmationDialog: a yes/no question.
struct Confirmation: Identifiable {
    let id = UUID()
    var message: String
    var positive = "Yes"
    var action: () -> Void
}

extension View {
    func confirmation(_ item: Binding<Confirmation?>) -> some View {
        alert(item.wrappedValue?.message ?? "", isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })) {
            let c = item.wrappedValue
            Button("No", role: .cancel) {}
            Button(c?.positive ?? "Yes") { c?.action() }
        }
    }
}

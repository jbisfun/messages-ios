import Contacts
import FossifyCommons
import SwiftUI

enum VCardFile {
    static func contacts(_ url: URL) -> [CNContact] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? CNContactVCardSerialization.contacts(with: data)) ?? []
    }

    static func displayName(_ c: CNContact) -> String {
        let n = CNContactFormatter.string(from: c, style: .fullName) ?? ""
        if !n.isEmpty { return n }
        if !c.organizationName.isEmpty { return c.organizationName }
        return c.phoneNumbers.first?.value.stringValue ?? c.emailAddresses.first.map { String($0.value) } ?? ""
    }

    static func names(_ url: URL) -> [String] { contacts(url).map(displayName) }
}

/// VCardViewerActivity: the contacts of a vCard attachment, expandable to their fields.
struct VCardViewerView: View {
    @Environment(\.palette) private var palette
    let attachment: Attachment
    @State private var expanded = Set<String>()
    @State private var share: ShareItems?

    var body: some View {
        let list = VCardFile.contacts(attachment.url)
        VStack(spacing: 0) {
            TopBar(title: "Contact details") {
                IconButton(icon: "person.badge.plus") {
                    if list.count == 1 { ContactUI.addContact(list[0]) } else { share = ShareItems([attachment.url]) }
                }
                .accessibilityLabel("Add contact")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, c in
                        let key = "\(i)"
                        Button {
                            if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
                        } label: {
                            HStack(spacing: 14) {
                                Avatar(name: VCardFile.displayName(c), image: c.thumbnailImageData ?? c.imageData, size: 48)
                                Text(VCardFile.displayName(c)).font(.system(size: palette.fontSize * 1.1))
                                Spacer()
                                Image(systemName: expanded.contains(key) ? "chevron.up" : "chevron.down")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if expanded.contains(key) {
                            ForEach(properties(c), id: \.0) { value, label, icon in
                                HStack(spacing: 16) {
                                    Image(systemName: icon).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(value).font(.system(size: palette.fontSize)).textSelection(.enabled)
                                        if !label.isEmpty {
                                            Text(label).font(.system(size: palette.fontSize * 0.75)).foregroundStyle(palette.secondaryText)
                                        }
                                    }
                                }
                                .padding(.leading, 78)
                                .padding(.trailing, 16)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear { if list.count == 1 { expanded = ["0"] } }
        .sheet(item: $share) { ShareSheet(items: $0.urls) }
    }

    /// VCardParser: the fields Fossify lists (phones, emails, addresses, organization, ...).
    private func properties(_ c: CNContact) -> [(String, String, String)] {
        func label(_ l: String?) -> String { l.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "" }
        var out: [(String, String, String)] = []
        for p in c.phoneNumbers { out.append((p.value.stringValue, label(p.label), "phone")) }
        for e in c.emailAddresses { out.append((String(e.value), label(e.label), "envelope")) }
        for a in c.postalAddresses {
            out.append((CNPostalAddressFormatter.string(from: a.value, style: .mailingAddress), label(a.label), "mappin.and.ellipse"))
        }
        if !c.organizationName.isEmpty || !c.jobTitle.isEmpty {
            out.append(([c.organizationName, c.jobTitle].filter { !$0.isEmpty }.joined(separator: ", "), "", "building.2"))
        }
        for u in c.urlAddresses { out.append((String(u.value), label(u.label), "link")) }
        if let b = c.birthday, let d = Calendar.current.date(from: b) {
            out.append((DateTimeFormat.format(d, DateTimeFormat.shared.dateFormat), "Birthday", "gift"))
        }
        if !c.note.isEmpty { out.append((c.note, "", "note.text")) }
        return out
    }
}

/// ManageBlockedKeywordsActivity.
struct ManageBlockedKeywordsView: View {
    @Environment(Config.self) private var config

    var body: some View {
        BlockedItemsView(
            title: "Manage blocked keywords",
            items: config.blockedKeywords.sorted(),
            placeholder: "You are not blocking any keywords. You may add keywords here to block all messages containing them.",
            addTitle: "Add a blocked keyword",
            importTitle: "Import blocked keywords",
            exportTitle: "Export blocked keywords",
            exportName: "Blocked keywords",
            fieldLabel: "Keyword",
            add: { config.blockedKeywords.insert($0) },
            remove: { _ = config.blockedKeywords.remove($0) })
    }
}

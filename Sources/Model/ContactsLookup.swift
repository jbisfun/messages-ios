import Contacts
import Foundation
import Observation

/// SimpleContact from the system address book (SimpleContactsHelper).
struct SimpleContact: Identifiable, Hashable {
    var id: String
    var name: String
    var numbers: [String]
    var thumbnail: Data?
}

/// Contacts.framework wrapper: names and photos for numbers, and the contact list
/// of the new conversation screen. READ_CONTACTS is optional on Android too.
@MainActor
@Observable
final class ContactsLookup {
    enum Access { case unknown, granted, denied }

    var access: Access = .unknown
    private(set) var contacts: [SimpleContact] = []
    @ObservationIgnored private var byNumber: [String: SimpleContact] = [:]
    @ObservationIgnored private let store = CNContactStore()

    nonisolated static let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
    ]

    func requestAccess() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            access = .granted
            reload()
        case .notDetermined:
            store.requestAccess(for: .contacts) { granted, _ in
                Task { @MainActor in
                    self.access = granted ? .granted : .denied
                    if granted { self.reload() }
                }
            }
        default:
            access = .denied
        }
    }

    func reload() {
        guard access == .granted else { return }
        let store = self.store
        Task.detached {
            var list: [SimpleContact] = []
            let req = CNContactFetchRequest(keysToFetch: ContactsLookup.keys)
            req.sortOrder = .userDefault
            try? store.enumerateContacts(with: req) { c, _ in
                let numbers = c.phoneNumbers.map(\.value.stringValue)
                guard !numbers.isEmpty else { return }
                var name = CNContactFormatter.string(from: c, style: .fullName) ?? ""
                if name.isEmpty { name = c.organizationName }
                if name.isEmpty { name = numbers[0] }
                list.append(SimpleContact(id: c.identifier, name: name, numbers: numbers, thumbnail: c.thumbnailImageData))
            }
            await MainActor.run { self.apply(list) }
        }
    }

    private func apply(_ list: [SimpleContact]) {
        contacts = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var map: [String: SimpleContact] = [:]
        for c in list {
            for n in c.numbers where !n.comparableNumber.isEmpty { map[n.comparableNumber] = map[n.comparableNumber] ?? c }
        }
        byNumber = map
    }

    func contact(for number: String) -> SimpleContact? {
        _ = contacts.count  // observe reloads
        let key = number.comparableNumber
        return key.isEmpty ? nil : byNumber[key]
    }

    /// getNameAndPhotoFromPhoneNumber(): the contact name, or the number itself.
    func name(for number: String) -> String { contact(for: number)?.name ?? number }

    func photo(for number: String) -> Data? { contact(for: number)?.thumbnail }

    /// The full CNContact for ContactsUI screens.
    func cnContact(id: String, keys: [CNKeyDescriptor]) -> CNContact? {
        try? store.unifiedContact(withIdentifier: id, keysToFetch: keys)
    }
}

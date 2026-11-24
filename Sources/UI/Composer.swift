import Contacts
import ContactsUI
import FossifyCommons
import MessageUI
import SwiftUI
import UIKit

/// sendMessageCompat(): iOS apps can't send SMS/MMS themselves, so every message goes
/// through the system composer (MFMessageComposeViewController), prefilled with the
/// recipients, text and attachments; the user confirms it there.
@MainActor
final class MessageComposer: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = MessageComposer()

    private var current: ComposeRequest?
    private weak var store: MessagesStore?

    func presentNext(_ store: MessagesStore) {
        guard current == nil, let r = store.composeQueue.first else { return }
        self.store = store
        guard MFMessageComposeViewController.canSendText() else {
            store.composeQueue.removeAll()
            store.toast = "Message not sent: sending method unsupported"
            r.onFinish?(false)
            return
        }
        guard let top = Launcher.topViewController() else { return }
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = self
        vc.recipients = r.recipients
        vc.body = r.body
        if MFMessageComposeViewController.canSendAttachments() {
            for a in r.attachments { _ = vc.addAttachmentURL(a.url, withAlternateFilename: a.filename) }
        }
        current = r
        top.present(vc, animated: true)
    }

    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                                  didFinishWith result: MessageComposeResult) {
        MainActor.assumeIsolated {
            controller.dismiss(animated: true) {
                guard let r = self.current, let store = self.store else { return }
                self.current = nil
                store.composeFinished(r, sent: result == .sent, failed: result == .failed)
                r.onFinish?(result == .sent)
                self.presentNext(store)
            }
        }
    }
}

/// Contacts app intents: contact details, "Add number to contact", contact picker.
@MainActor
enum ContactUI {
    /// startContactDetailsIntent().
    static func show(contactId: String, lookup: ContactsLookup) {
        guard let c = lookup.cnContact(id: contactId, keys: [CNContactViewController.descriptorForRequiredKeys()]) else { return }
        let vc = CNContactViewController(for: c)
        vc.allowsEditing = true
        present(vc)
    }

    /// ACTION_INSERT_OR_EDIT with the number prefilled.
    static func addNumber(_ number: String) {
        let c = CNMutableContact()
        c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: number))]
        let vc = CNContactViewController(forUnknownContact: c)
        vc.contactStore = CNContactStore()
        vc.allowsActions = false
        present(vc)
    }

    /// Adds the contacts of a vCard (VCardViewerActivity's "Add contact").
    static func addContact(_ contact: CNContact) {
        let vc = CNContactViewController(forNewContact: contact)
        vc.contactStore = CNContactStore()
        vc.delegate = NewContactDelegate.shared
        present(vc)
    }

    private static func present(_ vc: UIViewController) {
        let nav = UINavigationController(rootViewController: vc)
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in
            nav.dismiss(animated: true)
        })
        Launcher.topViewController()?.present(nav, animated: true)
    }

    final class NewContactDelegate: NSObject, CNContactViewControllerDelegate {
        static let shared = NewContactDelegate()
        func contactViewController(_ vc: CNContactViewController, didCompleteWith contact: CNContact?) {
            vc.dismiss(animated: true)
        }
    }
}

/// launchPickContactIntent(): CNContactPickerViewController, returning the picked contact.
struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { onPick(contact) }
    }
}

/// launchCapturePhotoIntent() / launchCaptureVideoIntent(): the system camera.
struct CameraPicker: UIViewControllerRepresentable {
    let video: Bool
    let onPick: (URL?, UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        vc.mediaTypes = [video ? "public.movie" : "public.image"]
        if video { vc.videoQuality = .typeMedium }
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onPick(info[.mediaURL] as? URL, info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

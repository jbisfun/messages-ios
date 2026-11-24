import Contacts
import FossifyCommons
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import _PhotosUI_SwiftUI
import _QuickLook_SwiftUI

/// The dialogs, pickers and previews of ThreadView.
struct ThreadSheets: ViewModifier {
    @Environment(MessagesStore.self) private var store
    @Environment(ContactsLookup.self) private var contacts
    @Environment(Config.self) private var config
    let view: ThreadView

    func body(content: Content) -> some View {
        let v = view
        content
            .sheet(isPresented: v.$scheduleDialog) {
                ScheduleMessageDialog(date: v.isScheduled ? v.scheduledDate : nil) { date in
                    v.scheduledDate = date
                    v.isScheduled = true
                    v.showPicker = false
                }
            }
            .sheet(item: v.$scheduledInfo) { m in
                RadioDialog(title: "Scheduled message", items: [(0, "Update message"), (1, "Send now"), (2, "Delete")],
                            selected: -1) { v.handleScheduled(m, action: $0) }
            }
            .sheet(isPresented: v.$deleteDialog) {
                let n = v.selection.count
                let toBin = config.useRecycleBin && !v.isRecycleBin
                DeleteConfirmationDialog(
                    message: toBin ? "Are you sure you want to move \(n.plural("message", "messages")) into the recycle bin?"
                        : "Are you sure you want to delete \(n.plural("message", "messages"))?",
                    showSkipRecycleBin: toBin) { v.deleteSelected(skipRecycleBin: $0) }
            }
            .sheet(item: v.$rename) { c in
                RenameConversationDialog(conversation: c) { store.rename(c.threadId, to: $0) }
            }
            .sheet(item: v.$details) { m in MessageDetailsDialog(message: m) }
            .sheet(item: Binding(get: { v.selectText.map(IdentifiedText.init) }, set: { v.selectText = $0?.text })) { t in
                SelectTextDialog(text: t.text)
            }
            .sheet(item: Binding(get: { v.shareText.map(IdentifiedText.init) }, set: { v.shareText = $0?.text })) { t in
                ShareSheet(items: [t.text])
            }
            .sheet(isPresented: v.$groupSendDialog) {
                GroupMessageSendDialog { asGroup in
                    config.sendGroupMessageMMS = asGroup
                    v.sendMessage(participants: store.participants(v.threadId, contacts: contacts))
                }
            }
            .alert("", isPresented: v.$shortCodeInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can only reply to short codes with numbers like \"503501\" but not to codes containing letters and numbers like \"AB-CD0\".")
            }
            .quickLookPreview(v.$quickLook)
            .fileExporter(isPresented: v.$exporting, documents: v.exportDocs, contentType: .data) { result in
                if case .success = result { store.toast = "File saved successfully" }
            }
            .photosPicker(isPresented: v.$photoPicker, selection: v.$photoItems, matching: .images)
            .photosPicker(isPresented: v.$videoPicker, selection: v.$photoItems, matching: .videos)
            .onChange(of: v.photoItems) { _, items in
                guard !items.isEmpty else { return }
                v.photoItems = []
                for item in items {
                    Task {
                        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                        let type = item.supportedContentTypes.first ?? .jpeg
                        let mime = type.preferredMIMEType ?? "application/octet-stream"
                        let ext = type.preferredFilenameExtension ?? "bin"
                        let prefix = Mime.isVideo(mime) ? "VID" : "IMG"
                        await MainActor.run {
                            v.addAttachment(data: data, mimetype: mime, filename: "\(prefix)_\(currentFormattedDateTime()).\(ext)")
                        }
                    }
                }
            }
            .fullScreenCover(item: Binding(get: { v.camera.map(CameraMode.init) }, set: { v.camera = $0?.video })) { mode in
                CameraPicker(video: mode.video) { url, image in
                    if let url, let data = try? Data(contentsOf: url) {
                        v.addAttachment(data: data, mimetype: Mime.type(for: url), filename: "VID_\(currentFormattedDateTime()).\(url.pathExtension)")
                    } else if let image, let data = image.jpegData(compressionQuality: 0.9) {
                        v.addAttachment(data: data, mimetype: "image/jpeg", filename: "IMG_\(currentFormattedDateTime()).jpg")
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: v.$recorder) {
                AudioRecorderSheet { url in
                    if let data = try? Data(contentsOf: url) {
                        v.addAttachment(data: data, mimetype: "audio/mp4", filename: url.lastPathComponent)
                    }
                }
            }
            .fileImporter(isPresented: v.$filePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        v.addAttachment(data: data, mimetype: Mime.type(for: url), filename: url.lastPathComponent)
                    }
                }
            }
            .sheet(isPresented: v.$contactPicker) {
                ContactPicker { contact in
                    // addContactAttachment(): the picked contact as a vCard.
                    let keys = [CNContactVCardSerialization.descriptorForRequiredKeys()]
                    let full = (try? CNContactStore().unifiedContact(withIdentifier: contact.identifier, keysToFetch: keys)) ?? contact
                    if let data = try? CNContactVCardSerialization.data(with: [full]) {
                        var name = CNContactFormatter.string(from: full, style: .fullName) ?? "contact"
                        if name.isEmpty { name = "contact" }
                        v.addAttachment(data: data, mimetype: "text/x-vcard", filename: name.replacingOccurrences(of: "/", with: "_") + ".vcf")
                    }
                }
            }
    }
}

struct CameraMode: Identifiable {
    let video: Bool
    var id: Bool { video }
}

struct IdentifiedText: Identifiable {
    let text: String
    var id: String { text }
}

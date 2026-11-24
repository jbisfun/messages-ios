import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// SettingsActivity.
struct SettingsView: View {
    @Environment(MessagesStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var dateTimeFormat = false
    @State private var fontSize = false
    @State private var lockScreen = false
    @State private var fileSize = false
    @State private var confirm: Confirmation?
    @State private var export = false
    @State private var exportFile: URL?
    @State private var importer = false
    @State private var importURL: URL?

    var body: some View {
        @Bindable var config = config
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsItem("Change date and time format") { dateTimeFormat = true }
                    SettingsItem("Manage blocked numbers") { router.push(.blockedNumbers) }
                    SettingsItem("Manage blocked keywords") { router.push(.blockedKeywords) }
                    SettingsItem("Font size", value: BaseConfig.shared.fontSize.title) { fontSize = true }

                    Text("Notifications").sectionHeader(palette)
                    SettingsItem("Customize notifications") {
                        Launcher.open(URL(string: UIApplication.openNotificationSettingsURLString))
                    }
                    SettingsItem("Lock screen notification visibility", value: LockScreen.title(config.lockScreenVisibilitySetting)) {
                        lockScreen = true
                    }

                    Text("Outgoing messages").sectionHeader(palette)
                    SettingsToggle("Show a character counter at writing messages", isOn: $config.showCharacterCounter)
                    SettingsToggle("Remove accents and diacritics at sending messages", isOn: $config.useSimpleCharacters)
                    SettingsToggle("Send message on pressing Enter", isOn: $config.sendOnEnter)
                    SettingsToggle("Send long messages as MMS", isOn: $config.sendLongMessageMMS)
                    SettingsToggle("Send group messages as MMS", isOn: $config.sendGroupMessageMMS)
                    SettingsItem("Resize sent MMS images", value: FileSize.title(config.mmsFileSizeLimit)) { fileSize = true }

                    Text("Archive").sectionHeader(palette)
                    SettingsToggle("Keep conversations archived", isOn: $config.keepConversationsArchived)

                    Text("Recycle bin").sectionHeader(palette)
                    SettingsToggle("Move deleted items to recycle bin", isOn: $config.useRecycleBin)
                    if config.useRecycleBin {
                        SettingsItem("Empty the recycle bin", value: store.recycleBinCount.plural("message", "messages")) { emptyRecycleBin() }
                    }

                    Text("Security").sectionHeader(palette)
                    PasswordProtectionToggle("Password protect the whole application", kind: .app)

                    Text("Migrating").sectionHeader(palette)
                    SettingsItem("Export messages") { export = true }
                    SettingsItem("Import messages") { importer = true }
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .confirmation($confirm)
        .sheet(isPresented: $dateTimeFormat) { ChangeDateTimeFormatDialog() }
        .sheet(isPresented: $fontSize) {
            RadioDialog(title: nil, items: FontSize.allCases.map { ($0, $0.title) }, selected: BaseConfig.shared.fontSize) {
                BaseConfig.shared.fontSize = $0
            }
        }
        .sheet(isPresented: $lockScreen) {
            RadioDialog(title: nil, items: [LockScreen.senderMessage, LockScreen.sender, LockScreen.nothing].map { ($0, LockScreen.title($0)) },
                        selected: config.lockScreenVisibilitySetting) { config.lockScreenVisibilitySetting = $0 }
        }
        .sheet(isPresented: $fileSize) {
            RadioDialog(title: nil, items: FileSize.all, selected: config.mmsFileSizeLimit) { config.mmsFileSizeLimit = $0 }
        }
        .sheet(isPresented: $export) {
            ExportMessagesDialog { url in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exportFile = url }
            }
        }
        .fileMover(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }), file: exportFile) { result in
            if case .success = result { store.toast = "Exporting successful" }
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.json, .xml, .plainText, .data]) { result in
            if case .success(let url) = result {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { importURL = url }
            }
        }
        .sheet(item: Binding(get: { importURL.map(IdentifiedURL.init) }, set: { importURL = $0?.url })) { ImportMessagesDialog(url: $0.url) }
    }

    private func emptyRecycleBin() {
        if store.recycleBinCount == 0 {
            store.toast = "The recycle bin is empty"
        } else {
            confirm = Confirmation(message: "Are you sure you want to empty the Recycle Bin? The messages will be permanently lost.") {
                store.emptyRecycleBin()
            }
        }
    }
}

extension AppInfo {
    public static let messages = AppInfo(
        name: "Messages", icon: "message.fill", upstream: "Messages", port: "messages-ios", policy: "messages",
        faq: [
            ("The other end is not receiving my MMS, is there anything I can do about it?",
             "MMS size is limited by carriers, you can try setting a smaller limit in the app settings."),
            ("Does the app support scheduled messages?",
             "Yes, you can schedule messages to be sent in the future by long pressing the Send button and picking the desired date and time."),
            ("Why do my group message replies appear as individual texts to recipients?",
             "You need to enable \"Send group messages as MMS\" in the app settings. This will ensure that group messages are sent as proper MMS, allowing all participants to see each other's replies."),
            ("How can I select multiple items at once?",
             "Start the selection mode by long pressing one item, then tap on others to select them."),
        ])
}

# messages-ios

[Fossify Messages](https://github.com/FossifyOrg/Messages) re-created for iOS in SwiftUI, sending through the system composer (`MessageUI`) with recipients from the system contact store (`Contacts.framework`).

    idl build -c release     # -> build/release/FossifyMessages.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyMessages

Ported: conversations with search (titles and message text), pinning, read/unread, rename, details, archive and recycle bin with all their actions; threads with date headers, sent/failed status, retry, multi-select copy/share/save/forward/select text/properties, linkified text and image/video/audio/vCard/file attachments; adding people, new conversation with suggestions and a letter index; attachment picker (photo, video, camera, audio, file, contact) with MMS image resizing; scheduled messages; drafts; blocked numbers and keywords with import/export; Fossify JSON (and SMS Backup & Restore XML) message import/export; date format, colors, font size, password protection and every applicable setting.

Differences forced by iOS: there is no SMS database or default SMS app role, so conversations are the ones imported from backups plus messages sent from the app, received texts never arrive and nothing gets blocked or notified on arrival; each message is confirmed in the system composer (Group MMS vs. separate messages is honored, SIM choice and delivery reports aren't available); scheduled messages raise a notification and open the composer when due instead of sending in the background; per-conversation notification channels, launcher shortcuts and "Use English" don't exist.

GPL-3.0, like the original.

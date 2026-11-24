import Foundation
import UIKit

// Fossify's JSON backup format (kotlinx.serialization of MessagesBackup): a list of
// SmsBackup / MmsBackup objects told apart by "backupType". Nulls are written
// explicitly and no other keys are allowed, so Android can import what we export.

struct SmsBackup: Codable {
    var subscriptionId: Int64
    var address: String
    var body: String?
    var date: Int64
    var dateSent: Int64
    var locked: Int
    var `protocol`: String?
    var read: Int
    var status: Int
    var type: Int
    var serviceCenter: String?
    var backupType = "sms"

    enum CodingKeys: String, CodingKey {
        case subscriptionId, address, body, date, dateSent, locked, `protocol`, read, status, type, serviceCenter, backupType
    }

    init(subscriptionId: Int64, address: String, body: String?, date: Int64, dateSent: Int64, locked: Int,
         protocol p: String?, read: Int, status: Int, type: Int, serviceCenter: String?) {
        self.subscriptionId = subscriptionId
        self.address = address
        self.body = body
        self.date = date
        self.dateSent = dateSent
        self.locked = locked
        self.protocol = p
        self.read = read
        self.status = status
        self.type = type
        self.serviceCenter = serviceCenter
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(subscriptionId, forKey: .subscriptionId)
        try c.encode(address, forKey: .address)
        try c.encode(body, forKey: .body)
        try c.encode(date, forKey: .date)
        try c.encode(dateSent, forKey: .dateSent)
        try c.encode(locked, forKey: .locked)
        try c.encode(`protocol`, forKey: .protocol)
        try c.encode(read, forKey: .read)
        try c.encode(status, forKey: .status)
        try c.encode(type, forKey: .type)
        try c.encode(serviceCenter, forKey: .serviceCenter)
        try c.encode(backupType, forKey: .backupType)
    }
}

struct MmsAddress: Codable {
    var address: String
    var type: Int
    var charset: Int

    static let from = 137
    static let to = 151
    static let cc = 130
    static let bcc = 129
}

struct MmsPart: Codable {
    var contentDisposition: String?
    var charset: String?
    var contentId: String?
    var contentLocation: String?
    var contentType: String
    var ctStart: String?
    var ctType: String?
    var filename: String?
    var name: String?
    var sequenceOrder: Int
    var text: String?
    var data: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contentDisposition, forKey: .contentDisposition)
        try c.encode(charset, forKey: .charset)
        try c.encode(contentId, forKey: .contentId)
        try c.encode(contentLocation, forKey: .contentLocation)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(ctStart, forKey: .ctStart)
        try c.encode(ctType, forKey: .ctType)
        try c.encode(filename, forKey: .filename)
        try c.encode(name, forKey: .name)
        try c.encode(sequenceOrder, forKey: .sequenceOrder)
        try c.encode(text, forKey: .text)
        try c.encode(data, forKey: .data)
    }

    /// MmsPart.isNonText().
    var isNonText: Bool {
        !(text != nil || contentType.lowercased().hasPrefix("text") || contentType.lowercased() == "application/smil")
    }
}

struct MmsBackup: Codable {
    var creator: String?
    var contentType: String?
    var deliveryReport: Int
    /// Seconds (Telephony.Mms.DATE).
    var date: Int64
    var dateSent: Int64
    var locked: Int
    var messageType: Int
    var messageBox: Int
    var read: Int
    var readReport: Int
    var seen: Int
    var textOnly: Int
    var status: String?
    var subject: String?
    var subjectCharSet: String?
    var subscriptionId: Int64
    var transactionId: String?
    var addresses: [MmsAddress]
    var parts: [MmsPart]
    var backupType = "mms"

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(creator, forKey: .creator)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(deliveryReport, forKey: .deliveryReport)
        try c.encode(date, forKey: .date)
        try c.encode(dateSent, forKey: .dateSent)
        try c.encode(locked, forKey: .locked)
        try c.encode(messageType, forKey: .messageType)
        try c.encode(messageBox, forKey: .messageBox)
        try c.encode(read, forKey: .read)
        try c.encode(readReport, forKey: .readReport)
        try c.encode(seen, forKey: .seen)
        try c.encode(textOnly, forKey: .textOnly)
        try c.encode(status, forKey: .status)
        try c.encode(subject, forKey: .subject)
        try c.encode(subjectCharSet, forKey: .subjectCharSet)
        try c.encode(subscriptionId, forKey: .subscriptionId)
        try c.encode(transactionId, forKey: .transactionId)
        try c.encode(addresses, forKey: .addresses)
        try c.encode(parts, forKey: .parts)
        try c.encode(backupType, forKey: .backupType)
    }
}

enum MessagesBackup: Codable {
    case sms(SmsBackup)
    case mms(MmsBackup)

    private enum TypeKey: String, CodingKey { case backupType }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        switch try c.decode(String.self, forKey: .backupType) {
        case "sms": self = .sms(try SmsBackup(from: decoder))
        case "mms": self = .mms(try MmsBackup(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .backupType, in: c, debugDescription: "No Serializer found")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .sms(let s): try s.encode(to: encoder)
        case .mms(let m): try m.encode(to: encoder)
        }
    }

    var isSms: Bool { if case .sms = self { return true } else { return false } }
}

enum BackupError: LocalizedError {
    case invalidFormat
    var errorDescription: String? { "Invalid file format" }
}

/// MessagesImporter / MessagesReader / MessagesWriter over the app's own store.
@MainActor
enum MessagesBackupIO {
    enum ImportResult { case ok, partial, fail, nothingNew }

    /// importMessages(): JSON (Fossify) or XML (SMS Backup & Restore).
    static func parse(_ data: Data) throws -> [MessagesBackup] {
        let head = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("<?xml") || head.hasPrefix("<smses") {
            return try XmlSmsParser.parse(data).map { .sms($0) }
        }
        do {
            return try JSONDecoder().decode([MessagesBackup].self, from: data)
        } catch {
            throw BackupError.invalidFormat
        }
    }

    /// restoreMessages().
    static func restore(_ backups: [MessagesBackup], into store: MessagesStore, contacts: ContactsLookup) -> ImportResult {
        let config = Config.shared
        var list: [(addresses: [String], message: Message)] = []
        var failed = 0
        // Our own numbers: the senders of sent MMS, to leave ourselves out of group threads.
        var own = Set<String>()
        for case .mms(let m) in backups where m.messageBox != 1 {
            for a in m.addresses where a.type == MmsAddress.from && a.address != "insert-address-token" {
                own.insert(a.address.comparableNumber)
            }
        }
        for b in backups {
            switch b {
            case .sms(let s) where config.importSms:
                list.append(([s.address], sms(s, contacts: contacts)))
            case .mms(let m) where config.importMms:
                if let item = mms(m, own: own, contacts: contacts) { list.append(item) } else { failed += 1 }
            default: break
            }
        }
        let (imported, _) = store.importMessages(list)
        if imported == 0 && failed == 0 { return .nothingNew }
        if failed > 0 { return imported > 0 ? .partial : .fail }
        return .ok
    }

    private static func sms(_ s: SmsBackup, contacts: ContactsLookup) -> Message {
        let received = s.type == MessageType.inbox
        return Message(
            id: 0, body: s.body ?? "", type: s.type, status: s.status,
            participants: [Participant(name: contacts.name(for: s.address), number: s.address)],
            date: Int(s.date / 1000), read: s.read == 1, threadId: 0, isMMS: false, attachments: [],
            senderPhoneNumber: received ? s.address : "", senderName: received ? contacts.name(for: s.address) : "",
            subscriptionId: Int(s.subscriptionId), isScheduled: false, dateMillis: s.date, dateSentMillis: s.dateSent)
    }

    private static func mms(_ m: MmsBackup, own: Set<String>, contacts: ContactsLookup) -> ([String], Message)? {
        let received = m.messageBox == 1
        let sender = m.addresses.first { $0.type == MmsAddress.from }?.address ?? ""
        var recipients = m.addresses.filter { [MmsAddress.to, MmsAddress.cc, MmsAddress.bcc].contains($0.type) }
            .map(\.address).filter { $0 != "insert-address-token" && !own.contains($0.comparableNumber) }
        if received {
            recipients = [sender] + recipients.filter { $0.comparableNumber != sender.comparableNumber }
        }
        recipients = recipients.filter { !$0.isEmpty }
        guard !recipients.isEmpty else { return nil }

        var body: [String] = []
        var attachments: [Attachment] = []
        for p in m.parts.sorted(by: { $0.sequenceOrder < $1.sequenceOrder }) {
            if p.contentType.lowercased() == "application/smil" { continue }
            if p.contentType.lowercased() == "text/plain", let t = p.text {
                body.append(t)
            } else if p.isNonText, let b64 = p.data, let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                let name = p.filename ?? p.name ?? p.contentLocation ?? "attachment"
                if let a = try? AttachmentFiles.save(data, mimetype: p.contentType, filename: name) { attachments.append(a) }
            }
        }
        let message = Message(
            id: 0, body: body.joined(separator: "\n"), type: received ? MessageType.inbox : MessageType.sent,
            status: MessageStatus.none,
            participants: recipients.map { Participant(name: contacts.name(for: $0), number: $0) },
            date: Int(m.date), read: m.read == 1, threadId: 0, isMMS: true, attachments: attachments,
            senderPhoneNumber: received ? sender : "", senderName: received ? contacts.name(for: sender) : "",
            subscriptionId: Int(m.subscriptionId), isScheduled: false, dateMillis: m.date * 1000,
            dateSentMillis: m.dateSent * 1000, subject: m.subject)
        return (recipients, message)
    }

    /// MessagesReader.getMessagesToExport().
    static func export(_ store: MessagesStore, sms getSms: Bool, mms getMms: Bool) -> [MessagesBackup] {
        var out: [MessagesBackup] = []
        for m in store.messages.sorted(by: { $0.millis < $1.millis }) where !m.isScheduled {
            let threadAddresses = store.threads[m.threadId]?.addresses ?? m.participants.map(\.number)
            if m.isMMS || !m.attachments.isEmpty {
                guard getMms else { continue }
                out.append(.mms(mmsBackup(m, addresses: threadAddresses)))
            } else {
                guard getSms else { continue }
                let address = m.isReceived && !m.senderPhoneNumber.isEmpty ? m.senderPhoneNumber : (threadAddresses.first ?? "")
                out.append(.sms(SmsBackup(
                    subscriptionId: Int64(m.subscriptionId), address: address, body: m.body, date: m.millis,
                    dateSent: m.dateSentMillis ?? 0, locked: 0, protocol: m.isReceived ? "0" : nil, read: m.read ? 1 : 0,
                    status: m.status, type: m.type, serviceCenter: nil)))
            }
        }
        return out
    }

    private static func mmsBackup(_ m: Message, addresses: [String]) -> MmsBackup {
        var addrs: [MmsAddress] = []
        if m.isReceived {
            addrs.append(MmsAddress(address: m.senderPhoneNumber, type: MmsAddress.from, charset: 106))
            for a in addresses where a.comparableNumber != m.senderPhoneNumber.comparableNumber {
                addrs.append(MmsAddress(address: a, type: MmsAddress.to, charset: 106))
            }
        } else {
            addrs.append(MmsAddress(address: "insert-address-token", type: MmsAddress.from, charset: 106))
            for a in addresses { addrs.append(MmsAddress(address: a, type: MmsAddress.to, charset: 106)) }
        }
        var parts: [MmsPart] = []
        var seq = 0
        if !m.body.isEmpty {
            parts.append(MmsPart(contentDisposition: nil, charset: "106", contentId: "<text_0>", contentLocation: "text_0.txt",
                                 contentType: "text/plain", ctStart: nil, ctType: nil, filename: nil, name: nil,
                                 sequenceOrder: seq, text: m.body, data: nil))
            seq += 1
        }
        for a in m.attachments {
            guard let data = try? Data(contentsOf: a.url) else { continue }
            parts.append(MmsPart(contentDisposition: nil, charset: nil, contentId: "<\(a.filename)>", contentLocation: a.filename,
                                 contentType: a.mimetype, ctStart: nil, ctType: nil, filename: a.filename, name: a.filename,
                                 sequenceOrder: seq, text: nil, data: data.base64EncodedString()))
            seq += 1
        }
        let seconds = m.millis / 1000
        return MmsBackup(
            creator: nil, contentType: "application/vnd.wap.multipart.related", deliveryReport: 129, date: seconds,
            dateSent: (m.dateSentMillis ?? 0) / 1000, locked: 0, messageType: m.isReceived ? 132 : 128,
            messageBox: m.isReceived ? 1 : (m.type == MessageType.failed ? 4 : 2), read: m.read ? 1 : 0, readReport: 129,
            seen: 1, textOnly: m.attachments.isEmpty ? 1 : 0, status: nil, subject: m.subject, subjectCharSet: nil,
            subscriptionId: Int64(m.subscriptionId), transactionId: nil, addresses: addrs, parts: parts)
    }

    static func encode(_ list: [MessagesBackup]) throws -> Data {
        try JSONEncoder().encode(list)
    }
}

/// XML import (<smses><sms address=… /></smses>), MessagesImporter.importXml().
final class XmlSmsParser: NSObject, XMLParserDelegate {
    private var items: [SmsBackup] = []
    private var sawRoot = false

    static func parse(_ data: Data) throws -> [SmsBackup] {
        let p = XmlSmsParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse(), p.sawRoot else { throw BackupError.invalidFormat }
        return p.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String] = [:]) {
        if name == "smses" { sawRoot = true }
        guard name == "sms", let address = a["address"], let date = Int64(a["date"] ?? "") else { return }
        items.append(SmsBackup(
            subscriptionId: 0, address: address, body: a["body"], date: date, dateSent: date,
            locked: Int(a["locked"] ?? "") ?? 0, protocol: a["protocol"], read: Int(a["read"] ?? "") ?? 1,
            status: Int(a["status"] ?? "") ?? -1, type: Int(a["type"] ?? "") ?? 1, serviceCenter: a["service_center"]))
    }
}

/// Files behind attachments.
enum AttachmentFiles {
    static func save(_ data: Data, mimetype: String, filename: String) throws -> Attachment {
        try FileManager.default.createDirectory(at: MessagesStore.attachmentsFolder, withIntermediateDirectories: true)
        var ext = (filename as NSString).pathExtension
        if ext.isEmpty { ext = Mime.ext(for: mimetype) }
        let id = UUID().uuidString + "." + ext
        try data.write(to: MessagesStore.attachmentsFolder.appendingPathComponent(id), options: .atomic)
        return Attachment(id: id, mimetype: mimetype, filename: filename)
    }

    static func copy(_ url: URL) throws -> Attachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try save(data, mimetype: Mime.type(for: url), filename: url.lastPathComponent)
    }

    /// ImageCompressor: re-encodes still images as JPEG until they fit the MMS size limit.
    static func compressImage(_ data: Data, limit: Int64) -> Data? {
        guard limit != FileSize.none, Int64(data.count) > limit, let image = UIImage(data: data) else { return nil }
        var img = image
        var quality: CGFloat = 0.9
        for _ in 0..<12 {
            if let out = img.jpegData(compressionQuality: quality), Int64(out.count) <= limit { return out }
            if quality > 0.4 {
                quality -= 0.15
            } else {
                let size = CGSize(width: img.size.width * 0.75, height: img.size.height * 0.75)
                img = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
            }
        }
        return nil
    }
}

import AVFoundation
import FossifyCommons
import SwiftUI
import UIKit

/// item_message: received (left, with sender photo) or sent (right, primary color) bubble.
struct MessageBubble: View {
    @Environment(\.palette) private var palette
    @Environment(ContactsLookup.self) private var contacts
    let message: Message
    let selected: Bool
    let onTapAttachment: (Attachment) -> Void
    let onTapSender: () -> Void

    var body: some View {
        let m = message
        let received = m.isReceived
        let senderName = received ? contacts.name(for: m.senderPhoneNumber.isEmpty ? (m.sender?.number ?? "") : m.senderPhoneNumber) : ""
        HStack(alignment: .bottom, spacing: 8) {
            if received {
                Avatar(name: senderName, image: contacts.photo(for: m.senderPhoneNumber), size: 36)
                    .onTapGesture(perform: onTapSender)
            } else {
                Spacer(minLength: 56)
            }
            VStack(alignment: received ? .leading : .trailing, spacing: 4) {
                ForEach(m.attachments) { a in
                    AttachmentView(attachment: a, sent: !received)
                        .onTapGesture { onTapAttachment(a) }
                }
                if !m.body.isEmpty {
                    bodyText(received: received)
                }
            }
            if received { Spacer(minLength: 56) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(selected ? palette.primaryColor.opacity(0.25) : Color.clear)
    }

    private func bodyText(received: Bool) -> some View {
        let fg = received ? palette.textColor : palette.onPrimary
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(message.body.linkified)
                .font(.system(size: palette.fontSize))
                .italic(message.isScheduled)
                .tint(received ? palette.primaryColor : palette.onPrimary)
                .foregroundStyle(fg)
                .multilineTextAlignment(.leading)
            if message.isScheduled {
                Image(systemName: "clock").font(.system(size: palette.fontSize * 0.8)).foregroundStyle(fg)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(received ? palette.textColor.opacity(palette.dark ? 0.16 : 0.08) : palette.primaryColor)
        )
    }
}

extension String {
    /// Linkify: web links and phone numbers become tappable.
    var linkified: AttributedString {
        var a = AttributedString(self)
        let types = NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        guard let detector = try? NSDataDetector(types: types) else { return a }
        for match in detector.matches(in: self, range: NSRange(location: 0, length: (self as NSString).length)) {
            guard let r = Range(match.range, in: self), let ar = Range(r, in: a) else { continue }
            if let url = match.url {
                a[ar].link = url
            } else if let p = match.phoneNumber, let url = URL(string: "tel:" + p.normalizedPhoneNumber) {
                a[ar].link = url
            }
            a[ar].underlineStyle = .single
        }
        return a
    }
}

/// Thread attachments: image/video thumbnail, audio player, vCard and file rows.
struct AttachmentView: View {
    @Environment(\.palette) private var palette
    let attachment: Attachment
    var sent = false

    var body: some View {
        let mime = attachment.mimetype
        if Mime.isImage(mime) {
            if let img = UIImage(contentsOfFile: attachment.url.path) {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxWidth: 240, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                fileRow(icon: "photo")
            }
        } else if Mime.isVideo(mime) {
            VideoThumbnail(url: attachment.url)
        } else if Mime.isAudio(mime) {
            AudioAttachmentRow(attachment: attachment)
        } else if Mime.isVCard(mime) {
            VCardRow(attachment: attachment)
        } else {
            fileRow(icon: mime == "application/pdf" ? "doc.richtext" : "doc")
        }
    }

    private func fileRow(icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename).font(.system(size: 15)).lineLimit(1)
                if let size = try? attachment.url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    Text(Int64(size).formattedByteSize).font(.system(size: 13)).opacity(0.7)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))
    }
}

extension Int64 {
    var formattedByteSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

struct VideoThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(Color.black.opacity(0.6)).frame(width: 200, height: 140)
            }
            Image(systemName: "play.circle").font(.system(size: 44)).foregroundStyle(.white)
        }
        .frame(maxWidth: 240, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: url) {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            if let cg = try? await gen.image(at: .zero).image { image = UIImage(cgImage: cg) }
        }
    }
}

/// AudioPlayerManager: one attachment plays at a time.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()
    private(set) var playing: URL?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playing == url {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        if player?.play() == true { playing = url }
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    func duration(_ url: URL) -> Int {
        Int((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = nil }
    }
}

struct AudioAttachmentRow: View {
    @Environment(\.palette) private var palette
    let attachment: Attachment
    private var playback: AudioPlayback { .shared }

    var body: some View {
        let isPlaying = playback.playing == attachment.url
        HStack(spacing: 10) {
            Button { playback.toggle(attachment.url) } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 32))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename).font(.system(size: 15)).lineLimit(1)
                Text(playback.duration(attachment.url).formattedDuration()).font(.system(size: 13)).opacity(0.7)
            }
        }
        .padding(12)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))
    }
}

/// item_attachment_vcard: the first contact's name and "and N others".
struct VCardRow: View {
    @Environment(\.palette) private var palette
    let attachment: Attachment

    var body: some View {
        let names = VCardFile.names(attachment.url)
        HStack(spacing: 10) {
            Avatar(name: names.first ?? "?", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(names.first ?? attachment.filename).font(.system(size: 15)).lineLimit(1)
                if names.count > 1 {
                    Text("and \((names.count - 1).plural("other", "others"))").font(.system(size: 13)).opacity(0.7)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.surface))
    }
}

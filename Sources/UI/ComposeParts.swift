import AVFoundation
import FossifyCommons
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// layout_attachment_picker: the eight colored buttons under the message field.
enum PickerAction: CaseIterable, Identifiable {
    case choosePhoto, chooseVideo, takePhoto, recordVideo, recordAudio, chooseFile, chooseContact, schedule

    var id: Self { self }

    var title: String {
        switch self {
        case .choosePhoto: return "Choose photo"
        case .chooseVideo: return "Choose video"
        case .takePhoto: return "Take photo"
        case .recordVideo: return "Record video"
        case .recordAudio: return "Record audio"
        case .chooseFile: return "Choose file"
        case .chooseContact: return "Choose contact"
        case .schedule: return "Schedule message"
        }
    }

    var icon: String {
        switch self {
        case .choosePhoto: return "photo"
        case .chooseVideo: return "video"
        case .takePhoto: return "camera"
        case .recordVideo: return "video.badge.plus"
        case .recordAudio: return "mic"
        case .chooseFile: return "doc"
        case .chooseContact: return "person"
        case .schedule: return "calendar.badge.clock"
        }
    }

    /// md_red_500, md_brown_500, md_pink_500, md_purple_500, md_teal_500, md_green_500, md_indigo_500, md_blue_500.
    var color: UInt32 {
        switch self {
        case .choosePhoto: return 0xFFF44336
        case .chooseVideo: return 0xFF795548
        case .takePhoto: return 0xFFE91E63
        case .recordVideo: return 0xFF9C27B0
        case .recordAudio: return 0xFF009688
        case .chooseFile: return 0xFF4CAF50
        case .chooseContact: return 0xFF3F51B5
        case .schedule: return 0xFF2196F3
        }
    }
}

struct AttachmentPickerGrid: View {
    let onPick: (PickerAction) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            ForEach(PickerAction.allCases) { a in
                Button { onPick(a) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: a.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color(argb: a.color)))
                        Text(a.title).font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
    }
}

/// Attachments waiting to be sent (AttachmentsAdapter), with remove buttons.
struct PendingAttachments: View {
    @Environment(\.palette) private var palette
    @Binding var attachments: [Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { a in
                    ZStack(alignment: .topTrailing) {
                        preview(a)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button {
                            attachments.removeAll { $0.id == a.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func preview(_ a: Attachment) -> some View {
        if Mime.isImage(a.mimetype), let img = UIImage(contentsOfFile: a.url.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            ZStack {
                palette.surface
                VStack(spacing: 4) {
                    Image(systemName: Mime.isVideo(a.mimetype) ? "video" : Mime.isAudio(a.mimetype) ? "music.note"
                        : Mime.isVCard(a.mimetype) ? "person.crop.square" : "doc").font(.system(size: 22))
                    Text(a.filename).font(.system(size: 10)).lineLimit(1).padding(.horizontal, 4)
                }
            }
        }
    }
}

/// launchCaptureAudioIntent(): Android hands off to a recorder app; iOS has none to call,
/// so this records an AAC clip with AVAudioRecorder.
struct AudioRecorderSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onDone: (URL) -> Void
    @State private var recorder: AVAudioRecorder?
    @State private var seconds = 0
    @State private var denied = false
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("Recording_\(currentFormattedDateTime()).m4a")

    var body: some View {
        DialogFrame(title: "Record audio", scroll: false) {
            VStack(spacing: 20) {
                Text(seconds.formattedDuration()).font(.system(size: 40, weight: .light).monospacedDigit())
                if denied {
                    Text("Microphone access is required").foregroundStyle(palette.secondaryText)
                }
                Button {
                    if recorder?.isRecording == true {
                        recorder?.stop()
                        onDone(url)
                        dismiss()
                    } else {
                        start()
                    }
                } label: {
                    Image(systemName: recorder?.isRecording == true ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(Color(argb: 0xFFF44336)))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .presentationDetents([.medium])
        .task(id: recorder?.isRecording == true) {
            while recorder?.isRecording == true {
                try? await Task.sleep(for: .seconds(1))
                seconds = Int(recorder?.currentTime ?? 0)
            }
        }
        .onDisappear { if recorder?.isRecording == true { recorder?.stop() } }
    }

    private func start() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                guard granted else { denied = true; return }
                try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]
                recorder = try? AVAudioRecorder(url: url, settings: settings)
                recorder?.record()
            }
        }
    }
}

/// ScheduleMessageDialog: date and time in the future.
struct ScheduleMessageDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State var date: Date
    let onPick: (Date) -> Void
    @State private var error: String?

    init(date: Date?, onPick: @escaping (Date) -> Void) {
        // Default: the next hour, minutes rounded to 5 like getNextHour()/getNextMinute().
        let base = date ?? {
            let cal = Calendar.current
            let now = Date()
            let minute = min(59, (cal.component(.minute, from: now) + 5 + 4) / 5 * 5)
            return cal.date(bySettingHour: min(23, cal.component(.hour, from: now) + 1), minute: minute, second: 0, of: now) ?? now.addingTimeInterval(3600)
        }()
        _date = State(initialValue: base)
        self.onPick = onPick
    }

    var body: some View {
        DialogFrame(title: "Schedule message") {
            Text("A notification reminds you at this time; open it to send the message.")
                .font(.system(size: 14)).foregroundStyle(palette.secondaryText).padding(.bottom, 8)
            DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, DateTimeFormat.shared.use24HourFormat ? Locale(identifier: "en_GB") : Locale(identifier: "en_US"))
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(.red)
            }
            DialogButtons {
                if date <= Date() {
                    error = "You must pick a time in the future"
                } else {
                    onPick(date)
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
    }
}

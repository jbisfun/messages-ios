import FossifyCommons
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension String {
    /// Digits and a leading '+', like PhoneNumberUtils.normalizeNumber. Non-numeric
    /// addresses (emails, alphanumeric senders) are kept as they are.
    var normalizedPhoneNumber: String {
        if contains(where: \.isLetter) || contains("@") { return trimmingCharacters(in: .whitespaces) }
        var out = ""
        for (i, ch) in self.enumerated() {
            if ch.isNumber, ch.isASCII { out.append(ch) } else if ch == "+" && i == 0 { out.append(ch) }
        }
        return out
    }

    /// String.trimToComparableNumber(): the last 9 digits, used to match numbers
    /// written with and without country codes.
    var comparableNumber: String {
        let n = normalizedPhoneNumber
        if n.contains(where: \.isLetter) || n.contains("@") { return n.lowercased() }
        let digits = n.filter(\.isNumber)
        return String(digits.suffix(9))
    }

    /// isShortCodeWithLetters(): alphanumeric senders can't be replied to (emails can).
    var isShortCodeWithLetters: Bool {
        if range(of: #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil { return false }
        return contains(where: \.isLetter)
    }

    /// java.lang.String.hashCode(), so letter avatars get the same color as on Android.
    var javaHashCode: Int32 {
        var h: Int32 = 0
        for u in utf16 { h = h &* 31 &+ Int32(u) }
        return h
    }

    /// String.getNameLetter(): first user visible grapheme, uppercased.
    var nameLetter: String {
        for ch in self where ch.isLetter || ch.isNumber || ch.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.value > 0x238C }) {
            return String(ch).uppercased()
        }
        return "A"
    }

    /// String.normalizeString(): strips accents and diacritics.
    var normalizedString: String { folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")) }

    /// Normalizes text for search: case/diacritic insensitive.
    var searchNormalized: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    /// String.isAValidFilename().
    var isAValidFilename: Bool {
        let illegal: Set<Character> = ["/", "\n", "\r", "\t", "\0", "`", "?", "*", "\\", "<", ">", "|", "\"", ":"]
        return !contains(where: { illegal.contains($0) })
    }
}

/// highlightTextPart(): colors every occurrence of `part` inside `text`.
func highlighted(_ text: String, _ part: String, color: Color) -> AttributedString {
    var a = AttributedString(text)
    guard !part.isEmpty else { return a }
    var searchRange = a.startIndex..<a.endIndex
    while let r = a[searchRange].range(of: part, options: [.caseInsensitive, .diacriticInsensitive]) {
        a[r].foregroundColor = color
        searchRange = r.upperBound..<a.endIndex
    }
    return a
}

/// SmsMessage.calculateLength(): (message count, code units remaining in the current part).
/// GSM 7-bit text fits 160 characters (153 per part when split), anything else UCS-2 70 (67).
enum SmsLength {
    private static let gsmBasic = Set("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà".unicodeScalars)
    private static let gsmExtended = Set("^{}\\[~]|€\u{0C}".unicodeScalars)

    static func calculate(_ text: String) -> (count: Int, remaining: Int) {
        var septets = 0
        var gsm = true
        for s in text.unicodeScalars {
            if gsmBasic.contains(s) { septets += 1 } else if gsmExtended.contains(s) { septets += 2 } else { gsm = false; break }
        }
        let units = gsm ? septets : text.utf16.count
        let single = gsm ? 160 : 70
        let multi = gsm ? 153 : 67
        if units <= single {
            return (1, single - units)
        }
        let count = (units + multi - 1) / multi
        return (count, count * multi - units)
    }
}

extension Int {
    /// Android quantity strings: "%d message" / "%d messages".
    func plural(_ one: String, _ other: String) -> String { "\(self) \(self == 1 ? one : other)" }
}

/// Long.formatDateOrTime(): time for today, else the configured date format (year
/// dropped for this year unless `showCurrentYear`), optionally followed by the time.
func formatDateOrTime(_ seconds: Int, hideTimeOnOtherDays: Bool, showCurrentYear: Bool) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(seconds))
    let f = DateTimeFormat.shared
    let cal = Calendar.current
    if cal.isDateInToday(date) { return f.formatTime(date) }
    var format = f.dateFormat
    if !showCurrentYear && cal.component(.year, from: date) == cal.component(.year, from: Date()) {
        format = format.replacingOccurrences(of: "y", with: "").trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-./"))
    }
    if !hideTimeOnOtherDays { format += ", \(f.timeFormat)" }
    return DateTimeFormat.format(date, format)
}

/// getTimeFormatWithSeconds().
var timeFormatWithSeconds: String { DateTimeFormat.shared.use24HourFormat ? "HH:mm:ss" : "hh:mm:ss a" }

/// getCurrentFormattedDateTime(): used for default export file names.
func currentFormattedDateTime() -> String { DateTimeFormat.format(Date(), "yyyy_MM_dd_HH_mm_ss") }

enum Mime {
    static func type(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    static func ext(for mime: String) -> String {
        UTType(mimeType: mime)?.preferredFilenameExtension ?? "bin"
    }

    static func isImage(_ m: String) -> Bool { m.lowercased().hasPrefix("image/") }
    static func isGif(_ m: String) -> Bool { m.lowercased() == "image/gif" }
    static func isVideo(_ m: String) -> Bool { m.lowercased().hasPrefix("video/") }
    static func isAudio(_ m: String) -> Bool { m.lowercased().hasPrefix("audio/") }
    static func isVCard(_ m: String) -> Bool {
        let l = m.lowercased()
        return l == "text/x-vcard" || l == "text/vcard" || l == "text/directory"
    }
}

extension Launcher {
    static func call(_ number: String) {
        open(URL(string: "tel:" + number.normalizedPhoneNumber))
    }
}

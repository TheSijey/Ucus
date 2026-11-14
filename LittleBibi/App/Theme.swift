import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

/// Mor ve şeftali tonları. Her rengin açık ve koyu mod karşılığı var.
enum Theme {
    static let bg = Color(light: 0xFFF6F2, dark: 0x15111C)
    static let card = Color(light: 0xFFFFFF, dark: 0x221B2E)
    static let primary = Color(light: 0x6B4AA0, dark: 0xBCA2EC)
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x1D1430)
    static let ink = Color(light: 0x35274F, dark: 0xF1EAFB)
    static let muted = Color(light: 0x6A5F7C, dark: 0xADA3BF)
    static let line = Color(light: 0xEFE6EE, dark: 0x33294A)

    static let feed = Color(light: 0xFFE2D2, dark: 0x4C3327)
    static let sleep = Color(light: 0xE7DFFB, dark: 0x382D57)
    static let diaper = Color(light: 0xD9ECF8, dark: 0x21394A)
    static let burp = Color(light: 0xDCF1E2, dark: 0x233F2D)
    static let note = Color(light: 0xFBDDE4, dark: 0x4B2933)

    static let feedInk = Color(light: 0x8A4A1F, dark: 0xFFC9A8)
    static let sleepInk = Color(light: 0x52398A, dark: 0xCDBCF5)
    static let diaperInk = Color(light: 0x1F5A7D, dark: 0xA9D6F0)
    static let burpInk = Color(light: 0x23633A, dark: 0xA8DDB8)
    static let noteInk = Color(light: 0x8A2D45, dark: 0xF5B5C4)

    static func tile(_ kind: EntryKind) -> Color {
        switch kind {
        case .nursing, .bottle: return feed
        case .sleep: return sleep
        case .diaper: return diaper
        case .burp: return burp
        case .note: return note
        }
    }

    static func tileInk(_ kind: EntryKind) -> Color {
        switch kind {
        case .nursing, .bottle: return feedInk
        case .sleep: return sleepInk
        case .diaper: return diaperInk
        case .burp: return burpInk
        case .note: return noteInk
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Bir kaydın satırı: simge, başlık, detay, saat ve giren kişi.
struct EntryRow: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.tileInk(entry.kind))
                .frame(width: 40, height: 40)
                .background(Theme.tile(entry.kind), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(3)
                }
                if entry.kind != .note, !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.time(entry.start))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                if !entry.author.isEmpty {
                    Text(entry.author)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

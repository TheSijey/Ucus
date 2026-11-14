import Foundation
import SwiftUI

/// Kabin arızası kategorisi.
enum DefectCategory: String, Codable, CaseIterable, Identifiable {
    case lavatory, galley, seat, ife, pa, light, door, oxygen, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lavatory: L("Tuvalet", "Lavatory")
        case .galley: L("Galley / Oven", "Galley / Oven")
        case .seat: L("Koltuk", "Seat")
        case .ife: "IFE"
        case .pa: L("PA / Interphone", "PA / Interphone")
        case .light: L("Işık", "Lights")
        case .door: L("Kapı / Slide", "Door / Slide")
        case .oxygen: L("Oksijen", "Oxygen")
        case .other: L("Diğer", "Other")
        }
    }

    var icon: String {
        switch self {
        case .lavatory: "toilet"
        case .galley: "cup.and.saucer"
        case .seat: "chair"
        case .ife: "tv"
        case .pa: "speaker.wave.2"
        case .light: "lightbulb"
        case .door: "door.left.hand.open"
        case .oxygen: "lungs"
        case .other: "ellipsis.circle"
        }
    }

    var color: Color {
        switch self {
        case .lavatory, .galley: Color(red: 1, green: 0.62, blue: 0.41)
        case .seat, .ife: Color(red: 0.56, green: 0.78, blue: 1)
        case .door, .oxygen: Color(red: 1, green: 0.45, blue: 0.45)
        default: Palette.secondary
        }
    }
}

/// Arızanın kabine etkisi.
enum DefectImpact: String, Codable, CaseIterable, Identifiable {
    case inop, limited, seatBlocked, informPax
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inop: L("Kullanım dışı", "Inoperative")
        case .limited: L("Kısıtlı çalışıyor", "Partly working")
        case .seatBlocked: L("Koltuk bloke", "Seat blocked")
        case .informPax: L("Yolcu bilgilendirilecek", "Inform passengers")
        }
    }
}

struct CabinDefect: Identifiable, Codable, Hashable {
    var id = UUID()
    var category: DefectCategory = .lavatory
    var location: String = ""
    var impacts: [DefectImpact] = []
    var note: String = ""

    /// "L2 · Kullanım dışı"
    var headline: String {
        var parts: [String] = []
        if !location.isEmpty { parts.append(location) }
        parts.append(contentsOf: impacts.map(\.title))
        return parts.isEmpty ? category.title : parts.joined(separator: " · ")
    }
}

/// Bir uçuşun brifing notları. Sadece bu cihazda, sadece o uçuş için tutulur.
struct BriefingNotes: Codable, Hashable {
    var defects: [CabinDefect] = []
    var crewNote: String = ""
    var drawing: Data? = nil
    var createdAt = Date()
    var dgItems: [DGItem]? = nil

    var isEmpty: Bool { defects.isEmpty && crewNote.isEmpty && drawing == nil && (dgItems ?? []).isEmpty }
}

@MainActor
final class BriefingStore: ObservableObject {
    static let shared = BriefingStore()
    private let key = "briefingNotes"

    @Published private(set) var all: [String: BriefingNotes] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let d = try? JSONDecoder().decode([String: BriefingNotes].self, from: data) {
            all = d
        }
        prune()
    }

    /// Uçuşun anahtarı: sefer + imza günü (UTC). Aynı seferin başka günü karışmaz.
    nonisolated static func key(for s: FlightAttributes.ContentState) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: s.signOn)
        return "\(s.flight)|\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    func notes(_ k: String) -> BriefingNotes { all[k] ?? BriefingNotes() }

    func update(_ k: String, _ change: (inout BriefingNotes) -> Void) {
        var n = notes(k)
        change(&n)
        all[k] = n.isEmpty ? nil : n
        save()
    }

    /// 4 günden eski notlar silinir.
    func prune() {
        let limit = Date().addingTimeInterval(-4 * 86_400)
        let before = all.count
        all = all.filter { $0.value.createdAt > limit }
        if all.count != before { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

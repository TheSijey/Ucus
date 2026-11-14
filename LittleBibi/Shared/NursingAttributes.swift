import ActivityKit
import Foundation

/// Emzirme sayacının Canlı Etkinlik verisi. Hem uygulama hem widget eklentisi kullanır.
struct NursingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "left", "right" ya da henüz taraf seçilmediyse "".
        var side: String
        /// Sayaç çalışıyorsa o tarafın başladığı an; duraklatıldıysa nil.
        var runningSince: Date?
        /// Biriken süreler (saniye), çalışan dilim hariç.
        var left: Double
        var right: Double
    }

    var babyName: String
}

extension NursingAttributes.ContentState {
    var sideTitle: String {
        switch side {
        case "left": return "Sol"
        case "right": return "Sağ"
        default: return "—"
        }
    }

    var isPaused: Bool { runningSince == nil }

    /// Seçili tarafın biriken süresi.
    var currentAccum: Double { side == "left" ? left : (side == "right" ? right : 0) }

    /// Diğer tarafın biriken süresi.
    var otherAccum: Double { side == "left" ? right : (side == "right" ? left : 0) }

    var otherTitle: String { side == "left" ? "Sağ" : "Sol" }

    /// Sayaç metninin sıfır noktası: bu tarihten itibaren geçen süre = tarafın toplam süresi.
    var timerOrigin: Date? {
        guard let since = runningSince else { return nil }
        return since.addingTimeInterval(-currentAccum)
    }
}

/// 08:42 ya da 1:08:42 biçiminde süre.
func clockText(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%02d:%02d", m, sec)
}

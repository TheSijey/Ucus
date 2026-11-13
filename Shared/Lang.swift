import Foundation

/// Uygulama dili: Ayarlar'daki seçim (Sistem / Türkçe / English). Widget de aynı seçimi okur.
enum Lang {
    static let key = "appLanguage"   // "system" | "tr" | "en"

    static var choice: String {
        SharedStore.defaults.string(forKey: key) ?? "system"
    }

    static var isEnglish: Bool {
        switch choice {
        case "tr": return false
        case "en": return true
        default: return !(Locale.preferredLanguages.first ?? "tr").hasPrefix("tr")
        }
    }

    /// Tarih biçimleri için yerel ayar.
    static var locale: Locale { Locale(identifier: isEnglish ? "en_GB" : "tr_TR") }
}

/// Türkçe ve İngilizce metinden geçerli dile uyanı.
@inline(__always)
func L(_ tr: String, _ en: String) -> String { Lang.isEnglish ? en : tr }

import Foundation
import WebKit

enum CDMError: LocalizedError {
    case empty, notFound

    var errorDescription: String? {
        switch self {
        case .empty: "Uçuş numarası ya da tescil yaz."
        case .notFound: "CDM'de bulunamadı ya da sayfa açılmadı. Numarayı kontrol edip tekrar dene."
        }
    }
}

/// mobilecdm.igairport.aero sayfasını görünmez bir tarayıcıda açıp sonucu okur.
/// (Site verileri JavaScript ile yüklediği için düz indirme yetmiyor.)
@MainActor
final class CDMFetcher {
    static let shared = CDMFetcher()
    private var webView: WKWebView?

    /// "TK1751" -> "1751", "TC-LTD" -> "LTD", " ltd " -> "LTD"
    static func normalize(_ raw: String) -> String {
        var q = raw.uppercased().replacingOccurrences(of: " ", with: "")
        if q.range(of: #"^TK\d"#, options: .regularExpression) != nil { q.removeFirst(2) }
        if q.range(of: #"^TC-?[A-Z]{3}$"#, options: .regularExpression) != nil { q = String(q.suffix(3)) }
        return q
    }

    func fetch(query raw: String) async throws -> FlightAttributes.ContentState {
        let q = Self.normalize(raw)
        guard !q.isEmpty,
              let url = URL(string: "https://mobilecdm.igairport.aero/#/flight/\(q)")
        else { throw CDMError.empty }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView = wv
        defer {
            wv.stopLoading()
            webView = nil
        }
        wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(700))
            let text = (try? await wv.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String ?? ""
            if text.contains("Stand"), text.contains("EOBT"),
               let info = CDMParser.parse(text) {
                return info
            }
        }
        throw CDMError.notFound
    }
}

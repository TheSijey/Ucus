import Foundation
import UIKit
import WebKit

enum CDMError: LocalizedError {
    case empty
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Uçuş numarası ya da tescil yaz."
        case .notFound(let pageText):
            let snippet = pageText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .prefix(300)
            return "CDM'den okunamadı.\n\nSayfada görünen: \(snippet.isEmpty ? "(boş)" : String(snippet))"
        }
    }
}

/// mobilecdm.igairport.aero sayfasını görünmez bir tarayıcıda açıp sonucu okur.
/// (Site verileri JavaScript ile yüklediği için düz indirme yetmiyor.)
@MainActor
final class CDMFetcher {
    static let shared = CDMFetcher()
    private var webView: WKWebView?

    static let base = "https://mobilecdm.igairport.aero/"
    static let safariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// "TK1751" -> "1751", "TC-LTD" -> "LTD", " ltd " -> "LTD"
    static func normalize(_ raw: String) -> String {
        var q = raw.uppercased().replacingOccurrences(of: " ", with: "")
        if q.range(of: #"^TK\d"#, options: .regularExpression) != nil { q.removeFirst(2) }
        if q.range(of: #"^TC-?[A-Z]{3}$"#, options: .regularExpression) != nil { q = String(q.suffix(3)) }
        return q
    }

    /// Arama kutusunu doldurup oka basar (sitenin kendi arayüzünü kullanır).
    private static func searchScript(_ q: String) -> String {
        """
        (function(q){
          var i = document.querySelector('input');
          if (!i) return 'noinput';
          var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(i, q);
          i.dispatchEvent(new Event('input', {bubbles:true}));
          i.dispatchEvent(new Event('change', {bubbles:true}));
          var b = document.querySelector('button') || document.querySelector('[role=button]');
          if (b) { b.click(); return 'clicked'; }
          ['keydown','keypress','keyup'].forEach(function(t){
            i.dispatchEvent(new KeyboardEvent(t, {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true}));
          });
          if (i.form) { i.form.requestSubmit ? i.form.requestSubmit() : i.form.submit(); }
          return 'enter';
        })(\(String(reflecting: q)));
        """
    }

    func fetch(query raw: String) async throws -> FlightAttributes.ContentState {
        let q = Self.normalize(raw)
        guard !q.isEmpty, let url = URL(string: Self.base + "#/flight/\(q)") else { throw CDMError.empty }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.customUserAgent = Self.safariUA
        wv.isUserInteractionEnabled = false
        wv.alpha = 0.01

        // Ekrana (görünmez şekilde) ekle ki iOS sayfayı gerçekten çizip çalıştırsın.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            window.insertSubview(wv, at: 0)
        }
        webView = wv
        defer {
            wv.stopLoading()
            wv.removeFromSuperview()
            webView = nil
        }

        wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))

        var lastText = ""
        var searchedManually = false
        let start = Date()
        while Date().timeIntervalSince(start) < 25 {
            try await Task.sleep(for: .milliseconds(700))
            lastText = (try? await wv.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String ?? ""

            if lastText.contains("Stand"), lastText.contains("EOBT"), let info = CDMParser.parse(lastText) {
                return info
            }

            // 4 sn sonra hâlâ arama ekranındaysa kutuya yazıp oka bas.
            if !searchedManually, Date().timeIntervalSince(start) > 4, lastText.contains("Search your flight") {
                searchedManually = true
                _ = try? await wv.evaluateJavaScript(Self.searchScript(q))
            }
        }
        throw CDMError.notFound(lastText)
    }
}

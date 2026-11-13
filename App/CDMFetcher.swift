import Foundation
import UIKit
import WebKit

enum CDMError: LocalizedError {
    case empty
    case notFound(String)
    case otherFlight(asked: String, got: String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return L("Uçuş numarası ya da tescil yaz.", "Enter a flight number or registration.")
        case .notFound(let pageText):
            let snippet = pageText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .prefix(300)
            return L("CDM'den okunamadı.\n\nSayfada görünen: ", "Couldn't read CDM.\n\nPage shows: ") + (snippet.isEmpty ? L("(boş)", "(empty)") : String(snippet))
        case .otherFlight(let asked, let got):
            return L("CDM'de \(asked) bulunamadı; arama \(got) uçuşunu getirdi. Uçuş CDM'de henüz görünmüyor olabilir, biraz sonra tekrar dene.", "\(asked) not found in CDM; the search returned \(got). The flight may not be in CDM yet, try again a bit later.")
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

    /// "1751" / "TK1751" -> "TK1751", "TC-LTD" / "ltd" -> "LTD".
    /// CDM sadece rakamla aranınca içinde o rakamlar geçen ilk uçuşu getirir (828 -> 3U3828), bu yüzden TK ön eki kalır.
    static func normalize(_ raw: String) -> String {
        var q = raw.uppercased().replacingOccurrences(of: " ", with: "")
        if q.range(of: #"^\d{1,4}[A-Z]?$"#, options: .regularExpression) != nil { q = "TK" + q }
        if q.range(of: #"^TK0*\d"#, options: .regularExpression) != nil { q = CDMParser.cleanFlight(q) }
        if q.range(of: #"^TC-?[A-Z]{3}$"#, options: .regularExpression) != nil { q = String(q.suffix(3)) }
        return q
    }

    /// Aranan bir uçuş numarasıysa, gelen sonucun gerçekten o uçuş olduğunu doğrular.
    static func verify(_ state: FlightAttributes.ContentState, query q: String) throws {
        guard q.range(of: #"^[A-Z0-9]{2}\d"#, options: .regularExpression) != nil,
              q.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) == nil else { return }
        if CDMParser.cleanFlight(state.flight) != CDMParser.cleanFlight(q) {
            throw CDMError.otherFlight(asked: q, got: state.flight)
        }
    }

    /// CDM sitesinin kendi veri servisi: hızlı, tarayıcı gerektirmez.
    static func fetchAPI(_ q: String) async throws -> FlightAttributes.ContentState? {
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: base + "Service/api/Flight/" + enc) else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("true", forHTTPHeaderField: "Auto-Refresh")
        req.setValue("iOS", forHTTPHeaderField: "Device-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return CDMParser.parseJSON(data)
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
        guard !q.isEmpty else { throw CDMError.empty }
        do {
            if let s = try await Self.fetchAPI(q) {
                try Self.verify(s, query: q)
                DebugLog.add("CDM servis: \(s.flight) stand \(s.stand)")
                return s
            }
        } catch let e as CDMError {
            throw e
        } catch {
            DebugLog.add("CDM servis hatası, tarayıcıyla deneniyor: \(error.localizedDescription)")
        }
        let s = try await fetchWeb(q)
        try Self.verify(s, query: q)
        return s
    }

    private func fetchWeb(_ q: String) async throws -> FlightAttributes.ContentState {
        guard let url = URL(string: Self.base + "#/flight/\(q)") else { throw CDMError.empty }

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

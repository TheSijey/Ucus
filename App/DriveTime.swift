import CoreLocation
import MapKit
import SwiftUI

/// Ev konumu: sadece bu telefonda saklanır; yol süresi için Apple Haritalar'a gider.
@MainActor
enum HomeLocation {
    private static let latKey = "homeLat", lonKey = "homeLon", labelKey = "homeLabel"

    static var coordinate: CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        guard d.object(forKey: latKey) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: d.double(forKey: latKey), longitude: d.double(forKey: lonKey))
    }
    static var label: String? { UserDefaults.standard.string(forKey: labelKey) }

    static func save(_ c: CLLocationCoordinate2D, label: String) {
        let d = UserDefaults.standard
        d.set(c.latitude, forKey: latKey)
        d.set(c.longitude, forKey: lonKey)
        d.set(label, forKey: labelKey)
        DriveTime.shared.clear()
    }

    static func clear() {
        let d = UserDefaults.standard
        [latKey, lonKey, labelKey].forEach { d.removeObject(forKey: $0) }
        DriveTime.shared.clear()
    }

    /// İstanbul Havalimanı
    nonisolated static let airport = CLLocationCoordinate2D(latitude: 41.2617, longitude: 28.7422)
}

/// Evden havalimanına sürüş süresi (o saatte beklenen trafikle).
@MainActor
final class DriveTime: ObservableObject {
    static let shared = DriveTime()
    @Published private(set) var cache: [Int: Int] = [:]   // çıkış (5 dk'ya yuvarlı) → dakika
    private var loading = Set<Int>()

    private func slot(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 300) }

    func clear() { cache = [:] }

    func minutes(for departure: Date) -> Int? { cache[slot(departure)] }

    func load(for departure: Date) async {
        guard let home = HomeLocation.coordinate else { return }
        let key = slot(departure)
        guard cache[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: home))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: HomeLocation.airport))
        req.transportType = .automobile
        req.departureDate = max(departure, Date())
        do {
            let eta = try await MKDirections(request: req).calculateETA()
            cache[key] = Int((eta.expectedTravelTime / 60).rounded())
        } catch {
            DebugLog.add("Yol süresi alınamadı: \(error.localizedDescription)")
        }
    }
}

/// "Bu saatte çıkarsan yol ~52 dk · imzadan 8 dk önce varırsın"
struct DriveInfoLine: View {
    let departure: Date
    let signOn: Date
    @ObservedObject private var drive = DriveTime.shared

    var body: some View {
        Group {
            if HomeLocation.coordinate != nil, let m = drive.minutes(for: departure) {
                let spare = Int(signOn.timeIntervalSince(departure.addingTimeInterval(Double(m) * 60)) / 60)
                HStack(spacing: 6) {
                    Image(systemName: spare >= 0 ? "car.fill" : "exclamationmark.triangle.fill")
                    Text(L("Trafikle yol ~\(Display.minutes(m))", "Drive ~\(Display.minutes(m)) with traffic") + " · "
                         + (spare >= 0 ? L("imzadan \(Display.minutes(spare)) önce varırsın", "you arrive \(Display.minutes(spare)) before sign-on")
                                       : L("imzaya \(Display.minutes(-spare)) geç kalabilirsin", "you may be \(Display.minutes(-spare)) late for sign-on")))
                }
                .font(.footnote.bold())
                .foregroundStyle(spare >= 0 ? Color.white.opacity(0.85) : Palette.warn)
            }
        }
        .task(id: Int(departure.timeIntervalSince1970 / 300)) { await drive.load(for: departure) }
    }
}

/// Tek seferlik konum (izin ister).
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?

    func get() async -> CLLocation? {
        await withCheckedContinuation { c in
            cont = c
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            switch m.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
            case .denied, .restricted: self.finish(nil)
            default: break
            }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        Task { @MainActor in self.finish(l.last) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
    private func finish(_ l: CLLocation?) {
        cont?.resume(returning: l)
        cont = nil
    }
}

/// Ayarlar'daki ev konumu bölümü.
struct HomeLocationSection: View {
    let leaveMinutes: Int
    @ObservedObject var session = FlightSession.shared
    @State private var address = ""
    @State private var label = HomeLocation.label
    @State private var working = false
    @State private var error: String?
    @State private var locator: OneShotLocation?

    var body: some View {
        Section {
            if let label {
                LabeledContent(L("Ev", "Home")) { Text(label).lineLimit(2).multilineTextAlignment(.trailing) }
                if leaveMinutes > 0, let s = session.state, !s.isOutstation {
                    DriveInfoLine(departure: s.signOn.addingTimeInterval(-Double(leaveMinutes) * 60), signOn: s.signOn)
                }
                Button(L("Ev konumunu kaldır", "Remove home location"), role: .destructive) {
                    HomeLocation.clear(); self.label = nil
                }
            } else {
                HStack {
                    TextField(L("Adres ya da semt", "Address or area"), text: $address)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.search)
                        .onSubmit { Task { await geocode() } }
                    if working { ProgressView() } else {
                        Button(L("Bul", "Find")) { Task { await geocode() } }.disabled(address.isEmpty)
                    }
                }
                Button { Task { await useCurrent() } } label: {
                    Label(L("Şu anki konumumu kullan", "Use my current location"), systemImage: "location")
                }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text(L("Ev konumu (yol süresi için)", "Home location (for drive time)"))
        } footer: {
            Text(L("Girersen, çıkış saatinde beklenen trafikle havalimanına yol süresi bilgi olarak gösterilir; çıkış saatini yine sen ayarlarsın. Konum sadece bu telefonda saklanır, rota için Apple Haritalar kullanılır.",
                   "If set, the expected drive time to the airport at your leave time is shown as information; you still choose the leave time. The location stays on this phone; Apple Maps is used for the route."))
        }
    }

    private func geocode() async {
        working = true; error = nil
        defer { working = false }
        let marks = try? await CLGeocoder().geocodeAddressString(address)
        guard let m = marks?.first, let c = m.location?.coordinate else {
            error = L("Adres bulunamadı.", "Address not found."); return
        }
        let text = [m.subLocality ?? m.name, m.locality].compactMap { $0 }.joined(separator: ", ")
        HomeLocation.save(c, label: text.isEmpty ? address : text)
        label = HomeLocation.label
    }

    private func useCurrent() async {
        working = true; error = nil
        defer { working = false }
        let l = OneShotLocation()
        locator = l
        guard let loc = await l.get() else {
            error = L("Konum alınamadı. Ayarlar'dan konum iznini kontrol et.", "Couldn't get your location. Check location permission in Settings."); return
        }
        let m = try? await CLGeocoder().reverseGeocodeLocation(loc).first
        let text = [m?.subLocality ?? m?.name, m?.locality].compactMap { $0 }.joined(separator: ", ")
        HomeLocation.save(loc.coordinate, label: text.isEmpty ? L("Şu anki konum", "Current location") : text)
        label = HomeLocation.label
        locator = nil
    }
}

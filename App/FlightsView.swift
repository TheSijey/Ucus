import SwiftUI

/// Uçuşlarım: sıradaki uçuş, liste, hızlı arama.
struct FlightsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: FlightStore
    @ObservedObject var session = FlightSession.shared
    @AppStorage(AppSettings.leaveMinutesKey) private var leaveMinutes = 60
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                if let e = model.error {
                    Section { Text(e).font(.footnote).foregroundStyle(.red) }
                }

                if let next = store.upcoming.first {
                    Section {
                        nextCard(next)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        Text(L("Sıradaki", "Next"))
                    }
                }

                Section {
                    if store.upcoming.count <= 1 {
                        Text(store.upcoming.isEmpty ? L("Henüz uçuş yok. + ile roster'daki uçuşlarını ekle.", "No flights yet. Add your roster flights with +.") : L("Başka uçuş yok.", "No other flights."))
                            .font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                    ForEach(store.upcoming.dropFirst()) { f in
                        row(f)
                            .swipeActions {
                                Button(L("Sil", "Delete"), role: .destructive) { store.delete(f) }
                            }
                    }
                } header: {
                    Text(L("Sonraki uçuşlar", "Upcoming flights"))
                } footer: {
                    Text(L("Silmek için sola kaydır.", "Swipe left to delete.") + (leaveMinutes > 0 ? L(" Çıkış bildirimi: imzadan \(Display.minutes(leaveMinutes)) önce.", " Leave alert: \(Display.minutes(leaveMinutes)) before sign-on.") : ""))
                }

                Section {
                    HStack {
                        TextField(L("Sefer (1751) ya da tescil (LTD)", "Flight (1751) or registration (LTD)"), text: $query)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit(search)
                        if model.loading { ProgressView() }
                    }
                    Button(action: search) {
                        Label(L("Bul ve takibi başlat", "Find and start tracking"), systemImage: "airplane.departure").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text(L("Hızlı arama", "Quick search"))
                } footer: {
                    Text(L("İstanbul kalkışı İGA CDM'den (imza = EOBT − 1:15), dış meydan kalkışı uçuş verisinden gelir.", "IST departures from İGA CDM (sign-on = EOBT − 1:15); outstation departures from flight data."))
                }

                // FAB'ın altında boşluk
                Section { EmptyView() } footer: { Color.clear.frame(height: 60) }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle(L("Uçuşlarım", "My Flights"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(L("Ayarlar", "Settings"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L("Uçuş ekle", "Add flight"))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { model.showAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Palette.ret, in: Circle())
                        .shadow(color: Palette.ret.opacity(0.35), radius: 12, y: 6)
                }
                .accessibilityLabel(L("Uçuş ekle", "Add flight"))
                .padding(20)
            }
        }
    }

    private func search() {
        focused = false
        let q = query
        Task { await model.start(query: q, plannedDay: nil) }
    }

    private func nextCard(_ f: PlannedFlight) -> some View {
        let isActive = session.state.map { FlightStore.normalizeFlight($0.flight) == FlightStore.normalizeFlight(f.flight) } ?? false
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayText(f.date)).font(.caption).foregroundStyle(Palette.secondary)
                    Text(f.flight).font(.title.bold().monospaced())
                }
                Spacer()
                if isActive {
                    Text(L("Takip ediliyor", "Tracking")).font(.caption.bold()).foregroundStyle(Palette.outbound)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Palette.outbound.opacity(0.15), in: Capsule())
                }
            }
            Button {
                Task { await model.start(planned: f) }
            } label: {
                HStack {
                    if model.loading { ProgressView().tint(.white) } else { Image(systemName: isActive ? "arrow.clockwise" : "location.fill") }
                    Text(isActive ? L("Takibi yenile", "Refresh tracking") : L("Takibi başlat", "Start tracking"))
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(Palette.ret, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.loading)
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func row(_ f: PlannedFlight) -> some View {
        Button {
            Task { await model.start(planned: f) }
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(weekday(f.date)).font(.caption2).foregroundStyle(Palette.secondary)
                    Text(dayNum(f.date)).font(.headline)
                }
                .frame(width: 44, height: 44)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.flight).font(.headline.monospaced())
                    Text(dayText(f.date)).font(.caption).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(Palette.stand)
            }
        }
        .foregroundStyle(.white)
        .disabled(model.loading)
    }

    private var utcCal: Calendar { UTC.calendar }

    private func dayText(_ d: Date) -> String {
        if utcCal.isDateInToday(d) { return L("Bugün", "Today") + " · " + UTCFormat.day(d) + " (UTC)" }
        if utcCal.isDateInTomorrow(d) { return L("Yarın", "Tomorrow") + " · " + UTCFormat.day(d) + " (UTC)" }
        return UTCFormat.day(d) + " (UTC)"
    }

    private func weekday(_ d: Date) -> String {
        var st = Date.FormatStyle.dateTime.weekday(.abbreviated)
        st.timeZone = UTC.zone
        st.locale = Lang.locale
        return d.formatted(st).uppercased(with: Lang.locale)
    }

    private func dayNum(_ d: Date) -> String { String(utcCal.component(.day, from: d)) }
}

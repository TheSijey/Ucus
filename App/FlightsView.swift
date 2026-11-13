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
                        Text("Sıradaki")
                    }
                }

                Section {
                    if store.upcoming.count <= 1 {
                        Text(store.upcoming.isEmpty ? "Henüz uçuş yok. + ile roster'daki uçuşlarını ekle." : "Başka uçuş yok.")
                            .font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                    ForEach(store.upcoming.dropFirst()) { f in
                        row(f)
                            .swipeActions {
                                Button("Sil", role: .destructive) { store.delete(f) }
                            }
                    }
                } header: {
                    Text("Sonraki uçuşlar")
                } footer: {
                    Text("Silmek için sola kaydır." + (leaveMinutes > 0 ? " Çıkış bildirimi: imzadan \(Display.minutes(leaveMinutes)) önce." : ""))
                }

                Section {
                    HStack {
                        TextField("Sefer (1751) ya da tescil (LTD)", text: $query)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit(search)
                        if model.loading { ProgressView() }
                    }
                    Button(action: search) {
                        Label("Bul ve takibi başlat", systemImage: "airplane.departure").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Hızlı arama")
                } footer: {
                    Text("Bilgi İGA CDM'den alınır. İmza = EOBT − 1:15.")
                }

                // FAB'ın altında boşluk
                Section { EmptyView() } footer: { Color.clear.frame(height: 60) }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .navigationTitle("Uçuşlarım")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Ayarlar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Uçuş ekle")
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
                .accessibilityLabel("Uçuş ekle")
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
                    Text("Takip ediliyor").font(.caption.bold()).foregroundStyle(Palette.outbound)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Palette.outbound.opacity(0.15), in: Capsule())
                }
            }
            Button {
                Task { await model.start(planned: f) }
            } label: {
                HStack {
                    if model.loading { ProgressView().tint(.white) } else { Image(systemName: isActive ? "arrow.clockwise" : "location.fill") }
                    Text(isActive ? "Takibi yenile" : "Takibi başlat")
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
        if utcCal.isDateInToday(d) { return "Bugün · " + UTCFormat.day(d) + " (UTC)" }
        if utcCal.isDateInTomorrow(d) { return "Yarın · " + UTCFormat.day(d) + " (UTC)" }
        return UTCFormat.day(d) + " (UTC)"
    }

    private func weekday(_ d: Date) -> String {
        var st = Date.FormatStyle.dateTime.weekday(.abbreviated)
        st.timeZone = UTC.zone
        st.locale = Locale(identifier: "tr_TR")
        return d.formatted(st).uppercased(with: Locale(identifier: "tr_TR"))
    }

    private func dayNum(_ d: Date) -> String { String(utcCal.component(.day, from: d)) }
}

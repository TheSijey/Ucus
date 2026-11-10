import ActivityKit
import SwiftUI

struct ContentView: View {
    @State private var query = ""
    @State private var info: FlightAttributes.ContentState?
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Sefer (1751) ya da tescil (LTD)", text: $query)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit { Task { await fetchAndStart() } }
                        if loading { ProgressView() }
                    }
                    Button {
                        Task { await fetchAndStart() }
                    } label: {
                        Label("Getir ve Ada'ya koy", systemImage: "airplane.departure")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("Bilgi İGA CDM'den alınır. İmza saati EOBT − 1:15, kaybolma imza + 30 dk.")
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if let info {
                    Section("Uçuş") {
                        row("Sefer", "\(info.flight)  →  \(Display.text(info.destination))")
                        row("Tescil", "\(Display.text(info.registration))  ·  \(Display.text(info.aircraftType))")
                        row("Gate", info.gate)
                        row("Stand", info.stand)
                        row("Pist", info.runway)
                    }
                    Section("Saatler (yerel)") {
                        LabeledContent("İmzaya kalan") {
                            SignOnCountdown(signOn: info.signOn)
                                .font(.title3.bold())
                                .foregroundStyle(.orange)
                        }
                        timeRow("İmza", info.signOn)
                        timeRow("EOBT", info.eobt)
                        timeRow("TOBT", info.tobt)
                        timeRow("TSAT", info.tsat)
                        timeRow("CTOT", info.ctot)
                        timeRow("Kaybolma", info.hideAt)
                    }
                    Section {
                        Button("Yenile") { Task { await refresh() } }
                        Button("Ada'dan kaldır", role: .destructive) {
                            Task {
                                await LiveActivityManager.endAll()
                                self.info = nil
                            }
                        }
                    }
                }
            }
            .navigationTitle("Uçuş")
            .task { loadCurrent() }
            .refreshable { await refresh() }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(Display.text(value)).font(.body.monospaced().bold())
        }
    }

    private func timeRow(_ title: String, _ date: Date?) -> some View {
        LabeledContent(title) {
            if let date {
                Text(date, format: .dateTime.hour().minute()).monospacedDigit()
            } else {
                Text("—")
            }
        }
    }

    private func loadCurrent() {
        if let a = LiveActivityManager.current {
            info = a.content.state
            query = a.attributes.query
        }
    }

    private func fetchAndStart() async {
        focused = false
        loading = true
        error = nil
        defer { loading = false }
        do {
            let state = try await CDMFetcher.shared.fetch(query: query)
            info = state
            if state.hideAt <= Date() {
                error = "Bu uçuşun imza + 30 dk süresi geçmiş, Ada'ya konmadı."
                return
            }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                error = "Ayarlar > Uçuş > Canlı Etkinlikler'i aç."
                return
            }
            try await LiveActivityManager.start(query: CDMFetcher.normalize(query), state: state)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        await FlightRefresher.refreshActive()
        loadCurrent()
    }
}

import SwiftUI

@main
struct LittleBibiApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "tr_TR"))
                .tint(Theme.primary)
                .fontDesign(.rounded)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var showNursing = false
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            TodayView(showNursing: $showNursing)
                .tabItem { Label("Bugün", systemImage: "house.fill") }
            HistoryView()
                .tabItem { Label("Geçmiş", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "person.crop.circle") }
        }
        .fullScreenCover(isPresented: $showNursing) {
            NursingView()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .onAppear {
            if !store.profile.onboarded { showOnboarding = true }
        }
        .onOpenURL { url in
            if url.host == "nursing", store.profile.onboarded { showNursing = true }
        }
    }
}

/// İlk açılışta bir kez sorulan temel bilgiler.
struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var role = "Anne"
    @State private var customName = ""
    @State private var babyName = ""
    @State private var born = false
    @State private var birthDate = Date()

    private let roles = ["Anne", "Baba", "Diğer"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LittleBibi'ye hoş geldiniz")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.ink)
                        Text("Küçük anlar, büyük anılar. Başlamak için birkaç bilgi yeterli; hepsini sonra Ayarlar'dan değiştirebilirsiniz.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }
                Section("Siz kimsiniz?") {
                    Picker("Kayıtlarda görünecek ad", selection: $role) {
                        ForEach(roles, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    if role == "Diğer" {
                        TextField("Adınız (ör. Babaanne)", text: $customName)
                    }
                }
                Section("Bebek") {
                    TextField("Bebeğin adı (isteğe bağlı)", text: $babyName)
                    Toggle("Bebek doğdu", isOn: $born)
                    if born {
                        DatePicker("Doğum tarihi", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    }
                }
                Section {
                    Button("Başla") {
                        var p = store.profile
                        let custom = customName.trimmingCharacters(in: .whitespaces)
                        p.myName = role == "Diğer" ? (custom.isEmpty ? "Diğer" : custom) : role
                        p.babyName = babyName.trimmingCharacters(in: .whitespaces)
                        p.birthDate = born ? birthDate : nil
                        p.onboarded = true
                        store.updateProfile(p)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Kurulum")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
